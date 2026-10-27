// 기능 분류: 로그인 웹 세션 · 자격 증명 경계 · 조회 브리지
import AppKit
import WebKit
import ZCRECore
import OSLog

@MainActor
final class WebSession: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    let webView: WKWebView
    var outputCache: [String: (until: Date, outputs: [JobOutput])] = [:]
    var outputsRetryAt = Date.distantPast
    var outputGeneration = 0
    private var window: NSWindow?
    private var popups: [NSWindow] = []
    private let script: String
    var didNavigate: (() -> Void)?
    var didChangeSession: (() -> Void)?
    private(set) var isLoaded = false
    private var started = false
    private var pendingSnapshot: PendingWebSnapshot?
    private var balanceRefreshUntil: Double = 0
    private var balanceRetryAt: Double = 0
    private var acceptedSnapshotRevision = ""
    private var candidateSnapshot: (revision: String, workspaceKey: String, fetchedAt: Date)?
    private(set) var retryNotBefore = Date.distantPast
    private let logger = Logger(subsystem: "kr.co.zcre.bunny.prototype", category: "connection")

    // MARK: - 웹 로그인 세션
    /// 앱 전용 WebKit 세션과 같은 출처의 로그인 변경 관찰 스크립트를 준비한다.
    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        if let url = Bundle.module.url(forResource: "ObserveSession", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            config.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1060, height: 740), configuration: config)
        script = Bundle.module.url(forResource: "ReadSnapshot", withExtension: "js").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "return JSON.stringify({error:'invalidResponse'});"
        super.init()
        config.userContentController.add(SessionMessageHandler(owner: self), name: "zcreSessionChanged")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    /// 인증 갱신을 유지할 ZCRE 크레딧 페이지를 한 번 로드한다. 페이지 자체 요청은 별도 발생할 수 있다.
    func start() {
        guard !started else { return }
        started = true
        // 계정 페이지를 유지해 Clerk 자체의 로그인 갱신이 작동하게 한다.
        webView.load(URLRequest(url: URL(string: "https://www.zcre.co.kr/credits")!))
    }

    /// 기존 웹 세션을 사용하는 로그인 창을 열고 입력 가능한 상태로 활성화한다.
    func show() {
        start()
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            panel.title = "\(AppInfo.name) · 계정 연결"
            panel.minSize = NSSize(width: 760, height: 560)
            panel.isReleasedWhenClosed = false
            panel.contentView = webView
            panel.center()
            window = panel
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 로그인 창만 숨긴다. 인증 세션과 페이지 스크립트는 유지된다.
    func hide() { window?.orderOut(nil) }

    // MARK: - 인증된 데이터 읽기
    /// 웹 내부에서 조회한 최소 메타데이터를 검증해 네이티브 모델로 변환한다. 토큰은 네이티브로 전달하지 않는다.
    func snapshot(activeIDs: [String], previous: WorkspaceSnapshot?, forceBalance: Bool = false) async throws -> WorkspaceSnapshot {
        start()
        // 페이지 새로고침을 로그아웃으로 취급하지 않고 계정 확인까지 추적 작업을 유지한다.
        guard isLoaded else { throw SnapshotError.network }
        guard let url = webView.url, url.scheme == "https", ["www.zcre.co.kr", "zcre.co.kr"].contains(url.host ?? "") else { throw SnapshotError.authentication }
        let requestedAt = Date.now
        let snapshotRevision = UUID().uuidString
        let formatter = ISO8601DateFormatter()
        var terminalCount = 0
        let recentJobs = previous?.jobs.filter { !$0.status.isTerminal || { terminalCount += 1; return terminalCount <= 50 }() }
        let priorJobs = recentJobs?.map { ["id": $0.id, "model": $0.model, "mediaType": $0.mediaType, "status": $0.status.rawValue, "createdAt": formatter.string(from: $0.createdAt)] } ?? []
        let priorBalance: [String: String] = previous.map { ["total": NSDecimalNumber(decimal: $0.balance.total).stringValue,
            "reserved": NSDecimalNumber(decimal: $0.balance.reserved).stringValue,
            "available": NSDecimalNumber(decimal: $0.balance.available).stringValue] } ?? [:]
        let json: String
        let pending = PendingWebSnapshot()
        pendingSnapshot?.finish(.failure(CancellationError()))
        pendingSnapshot = pending
        defer { if pendingSnapshot === pending { pendingSnapshot = nil } }
        do {
            json = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await pending.value {
                    webView.callAsyncJavaScript(script, arguments: [
                        "activeIDs": activeIDs, "previousJobs": priorJobs,
                        "previousWorkspaceKey": previous?.workspaceKey ?? "",
                        "previousHistoryTruncated": previous?.historyTruncated ?? false,
                        "since": previous.map { $0.fetchedAt.timeIntervalSince1970 * 1000 } ?? 0,
                        "previousBalance": priorBalance,
                        "previousBalanceFetchedAt": previous.map { $0.balanceFetchedAt.timeIntervalSince1970 * 1000 } ?? 0,
                        "previousBalanceIsStale": previous?.balanceIsStale ?? false,
                        "balanceRefreshUntil": balanceRefreshUntil, "balanceRetryAt": balanceRetryAt,
                        "forceBalance": forceBalance,
                        "snapshotRevision": snapshotRevision,
                        "acceptedSnapshotRevision": self.acceptedSnapshotRevision
                    ], in: nil, in: .page) { result in
                        pending.finish(result.flatMap { value in
                            guard let json = value as? String else { return .failure(SnapshotError.invalidResponse) }
                            return .success(json)
                        })
                    }
                }
            } onCancel: {
                Task { @MainActor in
                    if self.pendingSnapshot === pending { self.cancelSnapshot() }
                    else { pending.finish(.failure(CancellationError())) }
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if error as? SnapshotError == .network { webView.reload() }
            let error = error as NSError
            // 페이지 내용·자격 증명·식별자 대신 런타임 오류 코드만 로그에 남긴다.
            logger.error("Bridge runtime failure: code=\(error.code)")
            throw error
        }
        try Task.checkCancellation()
        guard let data = json.data(using: .utf8) else { throw SnapshotError.invalidResponse }
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let retry = payload?["retryAfter"] as? Double, retry.isFinite, retry > 0 {
            retryNotBefore = .now.addingTimeInterval(min(retry, 86400))
        }
        do {
            let snapshot = try SnapshotDecoder.decode(data, now: requestedAt)
            candidateSnapshot = (snapshotRevision, snapshot.workspaceKey, snapshot.fetchedAt)
            balanceRefreshUntil = payload?["balanceRefreshUntil"] as? Double ?? 0
            balanceRetryAt = payload?["balanceRetryAt"] as? Double ?? 0
            return snapshot
        }
        catch {
            if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let kind = payload["error"] as? String,
               ["authentication", "accountChanged", "invalidResponse", "unsupportedWorkspace", "http", "network"].contains(kind) {
                let status = payload["status"] as? Int ?? 0
                logger.error("Snapshot rejected: kind=\(kind, privacy: .public) status=\(status)")
            } else {
                logger.error("Snapshot decoding failed")
            }
            throw error
        }
    }

    /// 화면·감시 상태에 반영된 응답만 변경 캐시로 인정한다. 취소된 후보는 다음 조회에서 재확인한다.
    func acceptSnapshot(_ snapshot: WorkspaceSnapshot) {
        guard let candidateSnapshot,
              candidateSnapshot.workspaceKey == snapshot.workspaceKey,
              candidateSnapshot.fetchedAt == snapshot.fetchedAt else { return }
        acceptedSnapshotRevision = candidateSnapshot.revision
        self.candidateSnapshot = nil
    }

    // MARK: - 취소와 연결 해제
    /// 네이티브 대기와 브라우저 fetch를 함께 취소한다. 이미 서버가 받은 요청까지 되돌리지는 않는다.
    func cancelSnapshot() {
        pendingSnapshot?.finish(.failure(CancellationError()))
        webView.evaluateJavaScript("window.__zcreSupporterReadAbort?.abort()", completionHandler: nil)
    }

    /// 앱의 웹 데이터와 인증 갱신 상태를 지우고 빈 페이지로 전환한다.
    func disconnect() async {
        clearOutputs()
        cancelSnapshot()
        balanceRefreshUntil = 0; balanceRetryAt = 0; retryNotBefore = .distantPast
        acceptedSnapshotRevision = ""
        candidateSnapshot = nil
        webView.stopLoading()
        window?.orderOut(nil)
        for popup in popups { popup.close() }
        popups.removeAll()
        let store = webView.configuration.websiteDataStore
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        isLoaded = false; started = false
        webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
    }

    // MARK: - WebKit 탐색·로그인 콜백
    /// 허용된 HTTPS 페이지 로드가 끝나면 계정 조회를 재개할 수 있음을 알린다.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView, webView.url?.scheme == "https" else { return }
        isLoaded = true
        didNavigate?()
    }
    /// 페이지 이동이 시작되면 기존 브리지 응답을 취소해 서로 다른 페이지의 데이터를 섞지 않는다.
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        isLoaded = false
        pendingSnapshot?.finish(.failure(CancellationError()))
    }
    /// WebKit 프로세스 종료 시 대기 요청을 해제하고 페이지를 복구한다.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        isLoaded = false
        pendingSnapshot?.finish(.failure(CancellationError()))
        webView.reload()
    }
    /// 같은 WebView의 ZCRE 메인 프레임에서 온 준비·계정 변경 이벤트만 받아들인다.
    fileprivate func sessionChanged(_ message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard message.webView === webView, message.frameInfo.isMainFrame, origin.protocol == "https",
              ["www.zcre.co.kr", "zcre.co.kr"].contains(origin.host),
              let event = message.body as? String, ["ready", "changed"].contains(event) else { return }
        pendingSnapshot?.finish(.failure(CancellationError()))
        if event == "ready" { didNavigate?() } else { clearOutputs(); didChangeSession?() }
    }

    /// OAuth 로그인에 필요한 HTTPS 이동과 빈 페이지만 허용하고 다른 URL 스킴을 차단한다.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        // HTTPS 로그인 리디렉션은 WebKit 안에서 처리하고 사용자 모르게 외부 URL 핸들러를 실행하지 않는다.
        guard url.scheme == "https" || url.absoluteString == "about:blank" else { return .cancel }
        return .allow
    }

    /// 로그인 제공자가 요청한 팝업을 별도 창으로 열고 닫힘을 관리한다.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 680, height: 760), configuration: configuration)
        popup.navigationDelegate = self; popup.uiDelegate = self
        let panel = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "\(AppInfo.name) · 로그인"; panel.contentView = popup
        panel.isReleasedWhenClosed = false; panel.delegate = self
        panel.center(); panel.makeKeyAndOrderFront(nil)
        popups.append(panel)
        return popup
    }
    /// 웹 페이지가 닫기 요청을 보내면 대응하는 로그인 팝업을 닫는다.
    func webViewDidClose(_ webView: WKWebView) { popups.first { $0.contentView === webView }?.close() }
    /// 닫힌 팝업 창을 목록에서 제거한다.
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow { popups.removeAll { $0 === window } }
    }
}

@MainActor
private final class SessionMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: WebSession?
    /// 순환 참조를 피하도록 웹 세션 소유자를 약하게 보관한다.
    init(owner: WebSession) { self.owner = owner }
    /// WebKit 메시지를 출처 검증을 담당하는 세션으로 전달한다.
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.sessionChanged(message) }
}
