// 기능 분류: 계정 데이터의 단일 상태 · 폴링 · 알림 이력
import AppKit
import Observation
import Network
import UserNotifications
import ZCRECore

enum ConnectionState: Equatable {
    case signedOut, connecting, connected, delayed(String)
    var label: String {
        switch self {
        case .signedOut: "연결 대기"
        case .connecting: "연결 확인 중"
        case .connected: "연결됨"
        case .delayed: "갱신 지연"
        }
    }
}

@MainActor @Observable
final class CompanionStore {
    let preferences: Preferences
    var snapshot: WorkspaceSnapshot?
    var connection: ConnectionState = .signedOut
    var isRefreshing = false
    var isDemo = false
    var bubble: String?
    var notificationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var focusActive = false
    @ObservationIgnored private var focusTask: Task<Void, Never>?
    var isSleeping = false
    var lastEvent: String?
    var celebrationStart: Date?
    var failureStart: Date?
    private(set) var alerts: [CompanionAlert] = []
    private(set) var alertHistorySaveFailed = false
    private(set) var alertHistoryClearedThrough: Date?
    private(set) var debugModeEnabled = false
    @ObservationIgnored let webSession = WebSession()
    @ObservationIgnored let notifications = NotificationService()
    @ObservationIgnored private var monitor = Monitor()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var bubbleTask: Task<Void, Never>?
    @ObservationIgnored private var notificationTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var pollingAllowed = true
    @ObservationIgnored private var pollSchedule = AccountPollSchedule()
    @ObservationIgnored private var pendingBalanceRefresh = false
    @ObservationIgnored private let networkMonitor = NWPathMonitor()
    @ObservationIgnored private var networkMonitorStarted = false
    private(set) var isOffline = false
    @ObservationIgnored private var alertWorkspaceHash: String?
    @ObservationIgnored private var savedAlertHistory: AlertHistoryArchive?
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onAlert: ((CompanionAlert) -> Void)?
    @ObservationIgnored var onAlertsReset: (() -> Void)?
    @ObservationIgnored var openAlerts: (() -> Void)?
    @ObservationIgnored var showResult: ((GenerationJob) -> Void)?

    /// 저장된 해시를 현재 계정의 작업과 연결한다. 원문 ID나 서명 URL은 알림 파일에 저장하지 않는다.
    func job(for alert: CompanionAlert) -> GenerationJob? {
        snapshot?.jobs.first { historyKey(for: $0) == alert.jobKey }
    }

    // MARK: - 의존성 연결
    /// 웹 세션·알림 클릭 콜백을 연결한다. 모든 화면은 이 저장소의 동일한 스냅샷을 사용한다.
    init(preferences: Preferences) {
        self.preferences = preferences
        focusActive = preferences.isFocusActive()
        webSession.didNavigate = { [weak self] in self?.restartPolling() }
        webSession.didChangeSession = { [weak self] in self?.sessionChanged() }
        notifications.openAlerts = { [weak self] in self?.openAlerts?() }
    }

    /// 집중 설정 변경과 현지 시각 경계를 반영한다. 네트워크 요청은 발생하지 않는다.
    func refreshFocusPolicy() {
        focusTask?.cancel(); focusTask = nil
        let active = preferences.isFocusActive()
        let changed = focusActive != active
        focusActive = active
        if active {
            celebrationStart = nil; failureStart = nil; bubble = nil; lastEvent = nil
            bubbleTask?.cancel()
            for task in notificationTasks.values { task.cancel() }
            notificationTasks.removeAll()
            onAlertsReset?()
        }
        if changed { onChange?() }
        guard preferences.focusSchedule, !preferences.focusNow, !isSleeping else { return }
        // 분 경계에서만 재평가한다. 잠자기 중에는 예약하지 않는다.
        let delay = max(0.1, 60 - Date.now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60))
        focusTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.refreshFocusPolicy()
        }
    }

    // 검증된 작업 목록을 모든 화면이 공유한다. 지크를 숨겨도 이 데이터 경로는 유지한다.
    var activeJobs: [GenerationJob] { snapshot?.activeJobs ?? [] }
    var unreadAlertCount: Int { alerts.filter { !$0.isRead }.count }
    var creditText: String { snapshot.map { CreditBalance.format($0.balance.available) } ?? "—" }
    var isStale: Bool { if case .delayed = connection { true } else { false } }
    var delayMessage: String {
        if case .delayed(let reason) = connection { return reason }
        return "갱신이 지연돼 마지막 확인 값을 표시해요."
    }
    var companionMessage: String {
        if isDemo { return "미리보기로 함께 놀아봐요" }
        if snapshot == nil { return "연결하면 제가 지켜볼게요" }
        if isStale { return "연결을 다시 확인하고 있어요" }
        if !activeJobs.isEmpty { return "\(activeJobs.count)개의 작업을 지켜보고 있어요" }
        return "새로운 아이디어를 기다리고 있어요"
    }

    // MARK: - 연결과 로컬 데모
    /// 네트워크 가용성 관찰과 실제 또는 데모 데이터 감시를 시작하고 필요한 경우 알림 권한을 묻는다.
    func start(demo: Bool, reviewNotifications: Bool = true) {
        refreshFocusPolicy()
        if !networkMonitorStarted {
            networkMonitorStarted = true
            networkMonitor.pathUpdateHandler = { [weak self] path in
                let available = path.status != .unsatisfied
                Task { @MainActor in self?.networkChanged(available: available) }
            }
            networkMonitor.start(queue: DispatchQueue(label: "kr.co.zcre.bunny.network"))
        }
        if demo { enterDemo() } else { webSession.start(); refreshSoon() }
        Task {
            await refreshNotificationStatus()
            if !demo, reviewNotifications, NotificationService.shouldRequestOnLaunch(notificationStatus) {
                await enableNotifications()
            }
        }
    }
    /// 계정 연결 창을 열고 중단했던 실제 조회를 다시 시작한다.
    func connect() {
        if isDemo { leaveDemo() }
        pollingAllowed = true
        webSession.show()
        connection = .connecting
        restartPolling()
    }
    /// 진행 중인 조회를 취소하고 서버 호출 없이 데모 데이터와 알림 기준선을 만든다.
    func enterDemo() {
        generation += 1; pollTask?.cancel(); isRefreshing = false
        resetAlerts()
        isDemo = true; monitor.reset(); connection = .connected
        snapshot = DemoWorkspace.snapshot()
        _ = monitor.ingest(snapshot!, lowCreditThreshold: Decimal(preferences.lowCreditThreshold))
        importWorkHistory(snapshot!)
        say("안녕! 저는 지크 토끼예요")
        onChange?()
    }
    /// 데모 상태를 비운 뒤 실제 로그인 세션 조회로 복귀한다.
    func leaveDemo() {
        generation += 1; isDemo = false; snapshot = nil; monitor.reset()
        resetAlerts()
        connection = .signedOut; lastEvent = nil; bubble = nil
        pollingAllowed = true; webSession.start(); refreshSoon(); onChange?()
    }
    /// 데모 작업의 상태만 바꾸어 완료 이벤트 흐름을 확인한다. 실제 생성 요청은 보내지 않는다.
    func simulateCompletion() {
        guard isDemo else { return }
        let next = DemoWorkspace.snapshot(step: 1)
        let events = monitor.ingest(next, lowCreditThreshold: Decimal(preferences.lowCreditThreshold))
        snapshot = next
        if events.isEmpty { say("미리보기 작업이 이미 완료됐어요") }
        for event in events { handle(event) }
        onChange?()
    }
    /// 실제 계정·작업 상태를 변경하지 않고 완료 모션과 말풍선만 재생한다.
    func testCompletionMotion() {
        failureStart = nil
        celebrationStart = .now
        say("완료 모션 테스트예요!")
    }
    /// 서버 작업·알림을 만들지 않고 실패 때의 울음 모션만 재생한다.
    func testFailureMotion() {
        celebrationStart = nil
        failureStart = .now
        say("실패 모션 테스트예요")
    }
    // 개발용 컨트롤을 보여 주는 로컬 코드이며 계정 인증 정보가 아니다.
    /// 로컬 모션 테스트 UI를 여는 코드를 확인한다. 계정 인증이나 서버 권한을 부여하는 기능은 아니다.
    func unlockDebugMode(code: String) -> Bool {
        guard code.trimmingCharacters(in: .whitespacesAndNewlines) == "zcrenext" else { return false }
        debugModeEnabled = true
        return true
    }
    /// 현재 실행 세션의 디버그 모드를 끈다.
    func disableDebugMode() { debugModeEnabled = false }
    // MARK: - 계정 조회 스케줄과 상태 반영
    /// 현황 열기는 정상 5초 일정에 합친다. 잔액이 아직 신선하면 강제로 다시 읽지 않는다.
    func refreshForPresentation() {
        guard !isDemo, !isSleeping, pollingAllowed, !isRefreshing else { return }
        let now = Date.now
        if let snapshot, now.timeIntervalSince(snapshot.fetchedAt) < 5 { return }
        refreshSoon()
    }
    /// 한 번에 하나의 계정 조회를 예약한다. 작업은 정상 시 5초, 실패 시 제한된 지수 지연으로 재조회한다.
    func refreshSoon(forceBalance: Bool = false) {
        guard !isDemo, !isSleeping, !isOffline, pollingAllowed else { return }
        pendingBalanceRefresh = pendingBalanceRefresh || forceBalance
        guard !isRefreshing else { return }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            let wait = max(self.webSession.retryNotBefore.timeIntervalSinceNow,
                           self.pollSchedule.nextUptime - ProcessInfo.processInfo.systemUptime)
            if wait > 0 {
                do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            }
            guard !Task.isCancelled, !self.isOffline, !self.isSleeping else { return }
            let started = ProcessInfo.processInfo.systemUptime
            self.pollSchedule.started(at: started)
            let requestedBalance = self.pendingBalanceRefresh
            self.pendingBalanceRefresh = false
            await self.refresh(forceBalance: requestedBalance)
            guard !Task.isCancelled, !self.isDemo, !self.isSleeping, self.pollingAllowed else { return }
            self.pollSchedule.finished(started: started, at: ProcessInfo.processInfo.systemUptime,
                                       failures: self.failures, signedOut: self.connection == .signedOut,
                                       jitter: Double.random(in: 0...1))
            let delay = max(0, self.pollSchedule.nextUptime - ProcessInfo.processInfo.systemUptime)
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self.refreshSoon()
        }
    }
    /// 조회 세대 번호를 바꿔 이전 응답을 무효화하고 새 폴링 루프를 시작한다.
    private func restartPolling() {
        guard !isDemo, !isSleeping, pollingAllowed else { return }
        generation += 1
        pollTask?.cancel(); isRefreshing = false; failures = 0
        pollSchedule.resume(at: ProcessInfo.processInfo.systemUptime, jitter: Double.random(in: 0...1))
        refreshSoon()
    }
    /// 로그인 계정·조직 변경 시 기존 계정의 화면과 알림 기준선을 지우고 다시 조회한다.
    private func sessionChanged() {
        guard !isDemo, pollingAllowed else { return }
        // 이전 계정의 크레딧·작업·알림을 새 계정 화면에 남기지 않는다.
        snapshot = nil; monitor.reset(); resetAlerts()
        connection = .connecting
        onChange?()
        restartPolling()
    }
    /// 검증된 스냅샷을 원자적으로 반영하고 상태 전이를 알림으로 변환한다. 이전 세대의 응답은 버린다.
    private func refresh(forceBalance: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let thisGeneration = generation
        defer { if generation == thisGeneration { isRefreshing = false; onChange?() } }
        do {
            let next = try await webSession.snapshot(activeIDs: monitor.trackedActiveIDs, previous: snapshot, forceBalance: forceBalance)
            guard !Task.isCancelled, generation == thisGeneration else { return }
            webSession.acceptSnapshot(next)
            let wasDisconnected = snapshot == nil
            if let previous = snapshot, previous.workspaceKey != next.workspaceKey { resetAlerts() }
            restoreAlertHistory(for: next.workspaceKey)
            let events = monitor.ingest(next, lowCreditThreshold: Decimal(preferences.lowCreditThreshold))
            snapshot = next; connection = next.balanceIsStale ? .delayed("크레딧 갱신 지연 · 작업 상태는 최신이에요") : .connected; failures = 0
            if wasDisconnected { say("연결됐어요. 작업이 끝나면 알려줄게요!") }
            for event in events { handle(event) }
            importWorkHistory(next)
            persistAlertHistory()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == thisGeneration else { return }
            failures += 1
            if let error = error as? SnapshotError, error == .authentication || error == .accountChanged || error == .unsupportedWorkspace {
                snapshot = nil; monitor.reset()
                // 계정이 확인될 때까지 미검증 데이터를 화면에서 숨기되 보관 이력은 유지한다.
                resetAlerts()
                connection = error == .authentication ? .signedOut : .delayed(error.localizedDescription)
            } else {
                connection = .delayed((error as? SnapshotError)?.localizedDescription ?? SnapshotError.network.localizedDescription)
            }
        }
    }
    // MARK: - 연결 해제·오프라인·잠자기
    /// 자동 조회와 로컬 이력을 중단·삭제하고 앱의 웹 로그인 데이터를 비운다. 서버 계정 삭제는 하지 않는다.
    func disconnect() {
        generation += 1; pollingAllowed = false; pollTask?.cancel(); isRefreshing = false
        pendingBalanceRefresh = false
        resetAlerts()
        AlertHistoryArchive.remove()
        snapshot = nil; monitor.reset(); connection = .signedOut; bubble = nil; lastEvent = nil
        Task { await webSession.disconnect() }
        onChange?()
    }
    /// 오프라인에서는 진행 중인 조회를 취소하고 연결 복구 시 즉시 재조회한다.
    private func networkChanged(available: Bool) {
        guard isOffline == available else { return }
        isOffline = !available
        // 계정 감시가 꺼져 있어도 공개 상태 조회에는 네트워크 상태를 즉시 전달한다.
        defer { onChange?() }
        guard !isDemo, pollingAllowed else { return }
        if !available {
            generation += 1; pollTask?.cancel(); webSession.cancelSnapshot(); isRefreshing = false
            connection = .delayed("오프라인 · 마지막 확인한 현황이에요")
        } else {
            failures = 0
            pollSchedule.resume(at: ProcessInfo.processInfo.systemUptime, jitter: Double.random(in: 0...1))
            refreshSoon()
        }
    }
    /// 잠자기 동안 계정 조회를 취소하고 늦게 도착하는 응답도 무효화한다.
    func sleep() { isSleeping = true; focusTask?.cancel(); focusTask = nil; generation += 1; pollTask?.cancel(); webSession.cancelSnapshot(); isRefreshing = false }
    /// 깨우기 이후 정상 조회 예약을 재개한다.
    func wake() {
        isSleeping = false
        refreshFocusPolicy()
        pollSchedule.resume(at: ProcessInfo.processInfo.systemUptime, jitter: Double.random(in: 0...1))
        refreshSoon()
    }
    /// 새 말풍선을 표시하고 이전 타이머를 취소해 8초 후 닫는다.
    func say(_ message: String) {
        bubbleTask?.cancel(); bubble = message
        bubbleTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            self?.bubble = nil
        }
    }
    // MARK: - 알림 권한과 이벤트
    /// 이미 거부된 권한은 시스템 설정으로 안내하고 미결정 권한은 macOS 승인 창으로 요청한다.
    func enableNotifications() async {
        await refreshNotificationStatus()
        if notificationStatus == .denied { openNotificationSettings(); return }
        _ = await notifications.requestAuthorization()
        await refreshNotificationStatus()
    }
    /// macOS가 현재 허용한 알림 상태를 읽어 설정 화면에 반영한다.
    func refreshNotificationStatus() async { notificationStatus = await notifications.authorization() }
    /// 이 앱의 macOS 알림 설정 화면을 연다.
    func openNotificationSettings() { notifications.openSettings() }
    /// 로컬 테스트 알림을 만든다. ZCRE 서버의 작업이나 잔액에는 영향을 주지 않는다.
    func testNotification() async {
        guard !preferences.isFocusActive() else { return }
        await refreshNotificationStatus()
        if notificationStatus == .notDetermined { await enableNotifications() }
        say("알림 준비 완료! 작업이 끝나면 알려줄게요")
        let alert = recordAlert(kind: .completed, title: "알림 전달 테스트", body: "작업이 끝나면 이렇게 알려드려요. 지크를 숨기면 상단 바에서도 확인할 수 있어요.")
        let sent = await notifications.send(title: alert.title, body: alert.body, sound: preferences.sound, identifier: alert.id.uuidString)
        if !sent { say("앱 내 알림은 준비됐어요. 시스템 알림 권한도 확인해 주세요") }
    }
    /// 완료·실패·잔액 임계치 이벤트를 설정에 따라 표시하고 동일 작업 알림의 중복을 막는다.
    private func handle(_ event: MonitorEvent) {
        let quiet = preferences.isFocusActive()
        var present = !quiet
        let title: String; let body: String; let bubbleMessage: String; let kind: CompanionAlert.Kind
        let jobKey: String?
        switch event {
        case .completed(let job), .failed(let job): jobKey = historyKey(for: job)
        case .lowCredits: jobKey = nil
        }
        if let jobKey, alerts.contains(where: { $0.jobKey == jobKey }) { return }
        switch event {
        case .completed(let job):
            guard preferences.completionAlerts else { return }
            present = present && preferences.allowsJobAlert(job)
            if present { failureStart = nil; celebrationStart = .now }
            kind = .completed
            title = job.completionTitle; body = job.completionBody; bubbleMessage = job.completionBubble
        case .failed(let job):
            guard preferences.failureAlerts else { return }
            present = present && preferences.allowsJobAlert(job)
            if present { celebrationStart = nil; failureStart = .now }
            kind = .failed
            title = "\(job.workName) 확인 필요"; body = "\(job.startTimeLabel)에 시작한 작업이 실패했어요. ZCRE에서 자세한 내용을 확인해 주세요."
            bubbleMessage = "\(job.workName)\n\(job.startTimeLabel) 시작 · 작업 확인 필요"
        case .lowCredits(let value):
            guard preferences.lowCreditAlerts else { return }
            kind = .lowCredits
            title = "크레딧이 얼마 남지 않았어요"; body = "사용 가능한 크레딧이 \(CreditBalance.format(value)) 남았어요."
            bubbleMessage = title
        }
        let alert = recordAlert(kind: kind, title: title, body: body, jobKey: jobKey, present: present)
        guard present else { return }
        lastEvent = title; say(bubbleMessage)
        notificationTasks[alert.id] = Task { [weak self] in
            guard let self, !Task.isCancelled, !self.preferences.isFocusActive() else { return }
            _ = await self.notifications.send(title: alert.title, body: body, sound: self.preferences.sound, identifier: alert.id.uuidString)
            self.notificationTasks[alert.id] = nil
        }
    }
    /// 새 알림을 로컬 목록 앞에 추가하고 최근 30개만 보관한다.
    private func recordAlert(kind: CompanionAlert.Kind, title: String, body: String, jobKey: String? = nil, present: Bool = true) -> CompanionAlert {
        let alert = CompanionAlert(kind: kind, title: isDemo ? "[미리보기] \(title)" : title, body: body, jobKey: jobKey)
        alerts.insert(alert, at: 0)
        if alerts.count > 30 { alerts.removeLast(alerts.count - 30) }
        persistAlertHistory()
        onChange?()
        if present && !preferences.isFocusActive() { onAlert?(alert) }
        return alert
    }
    // MARK: - 알림 읽음·삭제·저장
    /// 지정한 개수 또는 전체 알림을 읽음 처리하고 변경된 이력을 저장한다.
    func markAlertsRead(limit: Int? = nil) {
        guard unreadAlertCount > 0 else { return }
        for index in alerts.indices.prefix(limit ?? alerts.count) { alerts[index].isRead = true }
        persistAlertHistory()
        onChange?()
    }
    /// 선택한 알림 하나만 읽음 처리한다.
    func markAlertRead(_ id: UUID) {
        if let index = alerts.firstIndex(where: { $0.id == id }), !alerts[index].isRead {
            alerts[index].isRead = true
            persistAlertHistory()
        }
        onChange?()
    }
    /// 현재 목록을 비우고 삭제 기준 시각을 남겨 과거 작업이 다시 알림으로 나타나지 않게 한다.
    func clearAlerts() {
        // 지운 목록은 갱신·재실행 후에도 다시 표시하지 않으며 새 상태 전이는 계속 알린다.
        alertHistoryClearedThrough = .now
        clearVisibleAlerts()
        persistAlertHistory()
    }
    /// 계정 전환용 알림 식별자·저장 기준과 표시 상태를 초기화한다.
    private func resetAlerts() {
        alertWorkspaceHash = nil
        savedAlertHistory = nil
        alertHistoryClearedThrough = nil
        alertHistorySaveFailed = false
        clearVisibleAlerts()
    }
    /// 화면 알림·예약된 macOS 알림·완료 모션을 함께 정리한다.
    private func clearVisibleAlerts() {
        for task in notificationTasks.values { task.cancel() }
        notificationTasks.removeAll()
        alerts.removeAll(); lastEvent = nil; celebrationStart = nil; failureStart = nil
        bubbleTask?.cancel(); bubble = nil
        notifications.clear()
        onAlertsReset?(); onChange?()
    }
    /// 현재 계정의 해시와 일치하는 로컬 알림 이력만 복원한다.
    private func restoreAlertHistory(for workspaceKey: String) {
        let workspaceHash = AlertHistoryArchive.key(workspaceKey)
        guard alertWorkspaceHash != workspaceHash else { return }
        alertWorkspaceHash = workspaceHash
        let archive = AlertHistoryArchive.load(workspaceHash: workspaceHash)
        savedAlertHistory = archive
        alerts = Array((archive?.alerts ?? []).prefix(30))
        alertHistoryClearedThrough = archive?.clearedThrough
    }
    /// 작업 식별자와 상태를 해시하여 로컬 이력의 중복 판별 키를 만든다.
    private func historyKey(for job: GenerationJob) -> String {
        AlertHistoryArchive.key("\(job.id):\(job.status.rawValue)")
    }
    /// 조회한 완료·실패 작업을 읽은 이력으로 가져온다. 과거 작업에 시스템 알림을 새로 보내지 않는다.
    private func importWorkHistory(_ snapshot: WorkspaceSnapshot) {
        let merged = AlertHistoryArchive.merging(alerts, jobs: snapshot.jobs, clearedThrough: alertHistoryClearedThrough, demo: isDemo)
        // 동일한 이력에는 관찰 가능한 배열을 다시 쓰지 않아 현황창의 불필요한 재계산을 막는다.
        if merged != alerts { alerts = merged }
    }
    /// 실제 계정의 이력이 바뀐 경우에만 파일에 저장해 반복 디스크 쓰기를 줄인다.
    private func persistAlertHistory() {
        guard !isDemo, let alertWorkspaceHash else { return }
        let archive = AlertHistoryArchive(
            workspaceHash: alertWorkspaceHash, alerts: alerts, clearedThrough: alertHistoryClearedThrough
        )
        guard archive != savedAlertHistory else { return }
        alertHistorySaveFailed = !archive.save()
        if !alertHistorySaveFailed { savedAlertHistory = archive }
    }
    /// 허용된 ZCRE 경로만 기본 브라우저로 연다.
    static func openWebsite(path: String = "/") {
        guard ["/", "/history", "/credits", "/mcp", "/status"].contains(path), let url = URL(string: "https://www.zcre.co.kr\(path)") else { return }
        NSWorkspace.shared.open(url)
    }
}
