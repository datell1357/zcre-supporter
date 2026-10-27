// 기능 분류: 공개 상태 조회 · 60초 캐시 · 조건부 요청 · 서버 재시도 대기
import Foundation
import Observation
import ZCRECore

/// 공개 서비스 상태는 계정 세션과 분리하며 창이 열린 동안만 자동 조회한다.
@MainActor @Observable
final class ServiceStatusStore {
    private(set) var snapshot: ServiceStatusSnapshot?
    private(set) var isRefreshing = false
    private(set) var hasError = false
    @ObservationIgnored private var serverAtReceipt = Date.now
    @ObservationIgnored private var receivedUptime: TimeInterval?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var monitoring = false
    @ObservationIgnored private var networkAvailable = true
    @ObservationIgnored private var pendingManualRefresh = false
    @ObservationIgnored private var schedule = PublicStatusSchedule()
    @ObservationIgnored private var etag: String?
    @ObservationIgnored private var lastModified: String?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let uptime: () -> TimeInterval
    @ObservationIgnored private let jitter: () -> Double
    private static let endpoint = URL(string: "https://www.zcre.co.kr/api/public/service-status?window=24h")!

    /// 운영에서는 쿠키·자격 증명·디스크 캐시 없는 세션을 사용하고 테스트에서는 모의 세션·시계를 주입한다.
    init(session: URLSession? = nil, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, jitter: @escaping () -> Double = { Double.random(in: 0...1) }) {
        self.uptime = uptime; self.jitter = jitter
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 10
            self.session = URLSession(configuration: configuration)
        }
    }

    // 응답의 서버 시각에 단조 시계의 경과 시간을 더해 기기 시각 변경 영향을 줄인다.
    var isUnavailable: Bool {
        guard let snapshot, let receivedUptime else { return true }
        return hasError || snapshot.isStale(serverNow: serverAtReceipt.addingTimeInterval(max(0, uptime() - receivedUptime)))
    }
    /// 최신 집계를 확인할 수 없으면 기존 정상 색상을 그대로 유지하지 않는다.
    func health(for model: ServiceStatusSnapshot.Model) -> ServiceHealth { isUnavailable ? .checking : model.health }

    /// 재개방도 성공 응답의 60초 캐시와 서버 대기를 공유한다.
    func start() {
        guard !monitoring else { return }
        monitoring = true
        refresh(manual: false)
    }
    /// 닫힘·잠자기에는 주기와 진행 요청만 취소하고 캐시·재시도 제한은 보존한다.
    func stop() {
        monitoring = false; pendingManualRefresh = false
        cancelRequests()
    }
    /// 오프라인에서는 반복 실패 요청을 만들지 않고 복구 후 필요한 조회만 재개한다.
    func setNetworkAvailable(_ available: Bool) {
        guard networkAvailable != available else { return }
        networkAvailable = available
        if !available { cancelRequests() }
        else if monitoring { refresh(manual: false) }
    }

    /// 수동·자동 조회를 하나로 합친다. 수동은 최소 5초, 자동은 60초이며 오류 대기는 모두 존중한다.
    @discardableResult func refresh(manual: Bool = true) -> Task<Void, Never>? {
        guard networkAvailable else { return nil }
        guard requestTask == nil else { return requestTask }
        pendingManualRefresh = pendingManualRefresh || manual
        guard schedule.begin(at: uptime(), manual: pendingManualRefresh) else { scheduleNext(); return nil }
        pendingManualRefresh = false
        pollingTask?.cancel(); pollingTask = nil
        generation += 1
        let current = generation
        isRefreshing = true
        requestTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == current {
                    self.isRefreshing = false; self.requestTask = nil
                    self.scheduleNext()
                }
            }
            var retryAfter: TimeInterval = 0
            do {
                var request = URLRequest(url: Self.endpoint)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                if self.snapshot != nil {
                    if let etag = self.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
                    else if let lastModified = self.lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
                }
                let (data, response) = try await self.session.data(for: request)
                try Task.checkCancellation()
                guard self.generation == current else { return }
                guard let http = response as? HTTPURLResponse,
                      http.url?.scheme == "https", http.url?.host == "www.zcre.co.kr",
                      http.url?.path == Self.endpoint.path else { throw SnapshotError.invalidResponse }
                let serverNow = Self.serverDate(from: http)
                retryAfter = HTTPRetryAfter.seconds(http.value(forHTTPHeaderField: "Retry-After"), relativeTo: serverNow)
                if http.statusCode == 304 {
                    guard self.snapshot != nil, self.etag != nil || self.lastModified != nil else { throw SnapshotError.invalidResponse }
                    // 304는 본문만 재사용한다. 집계 시각은 변경하지 않아 오래된 정상 상태를 숨기지 않는다.
                } else {
                    guard http.statusCode == 200, http.mimeType == "application/json", data.count <= 1_000_000 else { throw SnapshotError.invalidResponse }
                    let next = try ServiceStatusSnapshot.decode(data)
                    if self.snapshot != next { self.snapshot = next }
                    self.etag = Self.validator(http.value(forHTTPHeaderField: "ETag"))
                    self.lastModified = Self.validator(http.value(forHTTPHeaderField: "Last-Modified"))
                }
                self.serverAtReceipt = serverNow
                self.receivedUptime = self.uptime()
                self.schedule.succeeded(at: self.uptime())
                self.hasError = false
            } catch {
                guard !Task.isCancelled, self.generation == current else { return }
                self.schedule.failed(at: self.uptime(), retryAfter: retryAfter, jitter: self.jitter())
                self.hasError = true
            }
        }
        return requestTask
    }

    /// 다음 허용 시각에 하나의 대기 작업만 둔다. 긴 서버 대기도 실제 HTTP 재시도 없이 보존한다.
    private func scheduleNext() {
        pollingTask?.cancel(); pollingTask = nil
        guard monitoring, networkAvailable, requestTask == nil else { return }
        let wait = min(3600, max(0.05, schedule.nextUptime(manual: pendingManualRefresh) - uptime()))
        pollingTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            guard let self, self.monitoring, self.networkAvailable else { return }
            self.pollingTask = nil
            self.refresh(manual: false)
        }
    }
    /// 세대 번호로 늦은 응답을 무효화하며 요청 취소가 서버 처리 취소를 보장한다고 가정하지 않는다.
    private func cancelRequests() {
        generation += 1
        pollingTask?.cancel(); pollingTask = nil
        requestTask?.cancel(); requestTask = nil
        isRefreshing = false
    }
    /// 응답 검증자만 제한된 길이로 보관한다. 계정 자격 증명은 저장하지 않는다.
    private static func validator(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= 512,
              value.rangeOfCharacter(from: .newlines) == nil else { return nil }
        return value
    }
    /// HTTP Date와 Age로 응답의 서버 기준 시각을 계산한다.
    private static func serverDate(from response: HTTPURLResponse) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        let date = response.value(forHTTPHeaderField: "Date").flatMap(formatter.date(from:)) ?? .now
        let age = Double(response.value(forHTTPHeaderField: "Age") ?? "0") ?? 0
        return date.addingTimeInterval(age.isFinite ? max(0, age) : 0)
    }
}
