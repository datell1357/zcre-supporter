// 검증 분류: URLProtocol 대역으로 공개 상태 캐시·조건부 응답·오프라인을 검증한다. 외부 통신은 없다.
import Foundation
import Testing
@testable import ZCREBunny

private struct StatusReply: Sendable {
    var code = 200
    var headers: [String: String] = ["Content-Type":"application/json", "Date":"Tue, 14 Nov 2023 22:13:20 GMT", "ETag":"\"fixture-v1\""]
    var body = Data(#"{"calculated_at":"2023-11-14T22:13:20Z","stale":false,"window":"24h","granularity":"1h","measurement":"request_created_to_completed","models":[{"model_name":"fixture","label":"테스트","state":"operational","series":[{"variant":"standard","state":"operational","points":[{"state":"available"}]}]}]}"#.utf8)
}

// URLSession 작업 큐의 접근은 잠금으로 직렬화하고 요청·응답은 테스트 메모리에만 보관한다.
private final class StatusProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [StatusReply]
    private var captured: [URLRequest] = []
    init(_ replies: [StatusReply]) { self.replies = replies }
    var requests: [URLRequest] { lock.withLock { captured } }
    func next(_ request: URLRequest) -> StatusReply {
        lock.withLock { captured.append(request); return replies.isEmpty ? StatusReply(code: 500) : replies.removeFirst() }
    }
}

private final class StatusProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: StatusProbe?
    // 테스트 스위트가 직렬 실행하며 접근 자체도 URLSession 작업 큐와 동기화한다.
    static func use(_ probe: StatusProbe) { lock.withLock { current = probe } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let probe = Self.lock.withLock({ Self.current }) else { return }
        let reply = probe.next(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.code, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor private final class StatusClock { var now: TimeInterval = 0 }

@Suite(.serialized) @MainActor
struct ServiceStatusStoreTests {
    // 모든 공개 상태 요청을 대역으로 가로채고 실제 대기 없이 단조 시계를 전진시킨다.
    private func setup(_ replies: [StatusReply]) -> (ServiceStatusStore, StatusProbe, StatusClock, URLSession) {
        let probe = StatusProbe(replies)
        StatusProtocol.use(probe)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StatusProtocol.self]
        config.urlCache = nil
        let session = URLSession(configuration: config)
        let clock = StatusClock()
        return (ServiceStatusStore(session: session, uptime: { clock.now }, jitter: { 0 }), probe, clock, session)
    }

    // 재개방은 기존 캐시를 사용하며 수동 연속 클릭도 진행 중인 한 요청에 합친다.
    @Test func reopeningUsesFreshCacheAndManualRequestsCoalesce() async {
        let (store, probe, clock, session) = setup([StatusReply(), StatusReply()])
        defer { store.stop(); session.invalidateAndCancel() }
        let first = store.refresh(manual: false)
        _ = store.refresh()
        await first?.value
        #expect(probe.requests.count == 1)
        #expect(!store.isUnavailable)
        clock.now = 2
        store.start(); store.stop(); store.start(); store.stop()
        #expect(probe.requests.count == 1)
        #expect(store.refresh() == nil)
        clock.now = 5
        await store.refresh()?.value
        #expect(probe.requests.count == 2)
        #expect(probe.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "\"fixture-v1\"")
        #expect(probe.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    // 유효한 304는 본문을 재사용하되 집계가 5분 이상 오래되면 정상 상태를 표시하지 않는다.
    @Test func conditionalResponseDoesNotMakeAnOldAggregationFresh() async {
        let reply = StatusReply(code: 304, headers: ["Date":"Tue, 14 Nov 2023 22:20:00 GMT"], body: Data())
        let (store, probe, clock, session) = setup([StatusReply(), reply])
        defer { store.stop(); session.invalidateAndCancel() }
        await store.refresh(manual: false)?.value
        let before = store.snapshot
        clock.now = 60
        await store.refresh(manual: false)?.value
        #expect(probe.requests.count == 2)
        #expect(store.snapshot == before)
        #expect(!store.hasError)
        #expect(store.isUnavailable)
    }

    // 서버의 429 재시도 대기는 수동 갱신·창 재개방으로 우회할 수 없다.
    @Test func rateLimitSurvivesReopeningAndManualRefresh() async {
        let (store, probe, clock, session) = setup([StatusReply(code: 429, headers: ["Retry-After":"120"]), StatusReply()])
        defer { store.stop(); session.invalidateAndCancel() }
        await store.refresh()?.value
        #expect(store.hasError)
        clock.now = 60
        store.start(); store.stop()
        #expect(store.refresh() == nil)
        #expect(probe.requests.count == 1)
        clock.now = 120
        await store.refresh()?.value
        #expect(probe.requests.count == 2)
        #expect(!store.hasError)
    }

    // HTTP 날짜 형식의 서버 대기도 초 단위와 동일하게 존중한다.
    @Test func httpDateRetryIsRespected() async {
        let (store, probe, clock, session) = setup([StatusReply(code: 503, headers: ["Date":"Tue, 14 Nov 2023 22:13:20 GMT","Retry-After":"Tue, 14 Nov 2023 22:15:20 GMT"]),StatusReply()])
        defer { store.stop(); session.invalidateAndCancel() }
        await store.refresh()?.value
        clock.now = 119
        #expect(store.refresh() == nil)
        clock.now = 120
        await store.refresh()?.value
        #expect(probe.requests.count == 2)
    }

    // 오프라인에는 요청하지 않으며 취소된 응답을 뒤늦게 성공으로 표시하지 않는다.
    @Test func offlineAndCancelledRequestsCannotPublishSnapshots() async {
        let (store, probe, clock, session) = setup([StatusReply()])
        defer { store.stop(); session.invalidateAndCancel() }
        store.setNetworkAvailable(false)
        #expect(store.refresh() == nil)
        #expect(probe.requests.isEmpty)
        store.setNetworkAvailable(true)
        let pending = store.refresh()
        store.stop()
        await pending?.value
        #expect(store.snapshot == nil)
        #expect(!store.isRefreshing)
        // 취소했더라도 같은 시각에 다시 HTTP 요청을 시작하지 않는다.
        clock.now = 1
        #expect(store.refresh() == nil)
    }

    // 검증자 없는 서버에서도 일반 GET으로 갱신하며, 근거 없는 304는 오류로 처리한다.
    @Test func serverWithoutValidatorsStillRefreshesAndUnexpected304Fails() async {
        var noValidator = StatusReply()
        noValidator.headers.removeValue(forKey: "ETag")
        let (store, probe, clock, session) = setup([noValidator,StatusReply(code:304)])
        defer { store.stop(); session.invalidateAndCancel() }
        await store.refresh()?.value
        clock.now = 60
        await store.refresh(manual: false)?.value
        #expect(probe.requests.count == 2)
        #expect(probe.requests.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(store.hasError && store.isUnavailable)
    }
}
