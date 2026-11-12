// 외부 통신·화면 표시 없이 결과 다운로드와 수동 업데이트·진단의 경계를 검증한다.
import Foundation
import ImageIO
import Observation
import Testing
@testable import ZCREBunny

private struct TransferReply: Sendable {
    var status = 200
    var headers: [String: String] = [:]
    var chunks: [Data] = []
    var delay: TimeInterval = 0
    var hangs = false
}
private final class TransferProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [TransferReply]
    private var count = 0
    private var samples: [ResultTransferProgress] = []
    init(_ replies: [TransferReply]) { self.replies = replies }
    var requests: Int { lock.withLock { count } }
    var progress: [ResultTransferProgress] { lock.withLock { samples } }
    func record(_ value: ResultTransferProgress) { lock.withLock { samples.append(value) } }
    func next() -> TransferReply {
        lock.withLock { count += 1; return replies.isEmpty ? .init(status: 500) : replies.removeFirst() }
    }
}
private final class TransferProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var probe: TransferProbe?
    private let state = NSLock()
    private var stopped = false
    static func use(_ value: TransferProbe) { lock.withLock { probe = value } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let probe = Self.lock.withLock({ Self.probe }) else { return }
        let reply = probe.next()
        if reply.hangs { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
            guard !state.withLock({ stopped }) else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in reply.chunks {
                guard !state.withLock({ stopped }) else { return }
                client?.urlProtocol(self, didLoad: chunk)
            }
            if !state.withLock({ stopped }) { client?.urlProtocolDidFinishLoading(self) }
        }
    }
    override func stopLoading() { state.withLock { stopped = true } }
}

@Suite(.serialized) @MainActor
struct ResultReliabilityTests {
    private let url = URL(string: "https://cdn.example.test/output")!
    private func configure(_ replies: [TransferReply]) -> (URLSessionConfiguration, TransferProbe) {
        let probe = TransferProbe(replies)
        TransferProtocol.use(probe)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransferProtocol.self]
        config.urlCache = nil
        return (config, probe)
    }
    private func waitForRequest(_ probe: TransferProbe) async throws {
        let end = Date.now.addingTimeInterval(2)
        while probe.requests == 0 && Date.now < end { await Task.yield() }
        #expect(probe.requests > 0)
    }

    @Test func streamsChunksReportsKnownAndUnknownSizes() async throws {
        for headers in [["Content-Length": "6"], [:]] {
            let (config, probe) = configure([.init(headers: headers, chunks: [Data("abc".utf8), Data("def".utf8)])])
            let file = try await ResultTransfer(configuration: config, progress: { probe.record($0) }).fetch(url)
            defer { ResultTransfer.removeTemporary(file) }
            #expect(try Data(contentsOf: file) == Data("abcdef".utf8))
            #expect(probe.progress.last?.received == 6)
            if headers.isEmpty { #expect(probe.progress.last?.fraction == nil) }
            else { #expect(probe.progress.last?.fraction == 1) }
        }
    }

    @Test func cancellationReleasesAnUnresponsiveTransfer() async throws {
        let (config, probe) = configure([.init(hangs: true)])
        let operation = Task { try await ResultTransfer(configuration: config).fetch(url) }
        try await waitForRequest(probe)
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
    }

    @Test func rejectsOversizeWithAndWithoutLengthAndTruncatedData() async throws {
        for reply in [
            TransferReply(headers: ["Content-Length": "7"], chunks: [Data(repeating: 0, count: 7)]),
            TransferReply(chunks: [Data(repeating: 0, count: 3), Data(repeating: 0, count: 4)])
        ] {
            let (config, _) = configure([reply])
            await #expect(throws: ResultTransferError.tooLarge) {
                try await ResultTransfer(configuration: config, limit: 6).fetch(url)
            }
        }
        let (config, _) = configure([.init(headers: ["Content-Length": "10"], chunks: [Data("short".utf8)])])
        await #expect(throws: ResultTransferError.truncated) { try await ResultTransfer(configuration: config).fetch(url) }
    }

    @Test func lowDiskSpaceRejectsBeforeSavingData() async throws {
        let (config, _) = configure([.init(headers: ["Content-Length": "500"], chunks: [Data(repeating: 0, count: 500)])])
        await #expect(throws: ResultTransferError.insufficientSpace) {
            try await ResultTransfer(configuration: config, capacity: { _ in 100 }).fetch(url)
        }
    }

    @Test func expiredURLRefreshesOnceAndNeverLoopsOrRetriesOtherErrors() async throws {
        var calls = 0, refreshes = 0
        let newer = URL(string: "https://cdn.example.test/fresh")!
        let file = try await ResultDownload.fetch(initial: url, refreshedURL: { refreshes += 1; return newer }, transfer: { value in
            calls += 1
            if calls == 1 { #expect(value == url); throw ResultTransferError.http(403) }
            #expect(value == newer)
            return newer
        })
        #expect(file == newer && calls == 2 && refreshes == 1)
        calls = 0; refreshes = 0
        await #expect(throws: ResultTransferError.http(403)) {
            try await ResultDownload.fetch(initial: url, refreshedURL: { refreshes += 1; return newer }, transfer: { _ in calls += 1; throw ResultTransferError.http(403) })
        }
        #expect(calls == 2 && refreshes == 1)
        calls = 0; refreshes = 0
        await #expect(throws: ResultTransferError.http(500)) {
            try await ResultDownload.fetch(initial: url, refreshedURL: { refreshes += 1; return newer }, transfer: { _ in calls += 1; throw ResultTransferError.http(500) })
        }
        #expect(calls == 1 && refreshes == 0)
    }

    @Test func completedFileReplacesAtomicallyButFailureAndCancelKeepExistingFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source")
        let destination = folder.appendingPathComponent("result")
        try Data("old".utf8).write(to: destination)
        #expect(throws: (any Error).self) { try ResultTransfer.save(folder.appendingPathComponent("missing"), to: destination) }
        #expect(try Data(contentsOf: destination) == Data("old".utf8))
        try Data("new".utf8).write(to: source)
        let operation = Task { try await Task.sleep(for: .seconds(10)); try ResultTransfer.save(source, to: destination) }
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(try Data(contentsOf: destination) == Data("old".utf8))
        try ResultTransfer.save(source, to: destination)
        #expect(try Data(contentsOf: destination) == Data("new".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).allSatisfy { !$0.hasPrefix(".zcre-save-") })
    }

    @Test func nativeDeadlineRejectsAndIgnoresLateWebKitReply() async throws {
        let pending = PendingWebSnapshot()
        await #expect(throws: URLError(.timedOut)) {
            try await pending.value(timeout: .milliseconds(5), timeoutError: URLError(.timedOut), start: {})
        }
        pending.finish(.success("late reply"))
    }

    @Test func forcedMetadataRefreshBypassesCacheAndClearingCancelsNativeWait() async throws {
        let web = WebSession()
        let item = try JSONDecoder().decode(JobOutput.self, from: Data(#"{"id":"one","url":"https://cdn.example.test/result.png","contentType":"image/png"}"#.utf8))
        web.outputCache["account:job"] = (.now.addingTimeInterval(30), [item])
        #expect(try await web.outputs(for: "job", workspace: "account").first?.id == "one")
        // 웹이 아직 로드되지 않은 상태이므로 강제 갱신은 캐시 대신 실패해야 한다.
        await #expect(throws: (any Error).self) { try await web.outputs(for: "job", workspace: "account", forceRefresh: true) }
        let pending = PendingWebSnapshot()
        web.pendingOutputs = pending
        web.clearOutputs()
        await #expect(throws: CancellationError.self) { try await pending.value(start: {}) }
        #expect(web.outputCache.isEmpty)
    }

    @Test func diagnosticsHaveFixedKeysAndNoFreeTextOrURLs() throws {
        let metrics = DiagnosticMetrics()
        metrics.record(.resultLookup, started: ProcessInfo.processInfo.systemUptime, outcome: .success, status: 200)
        metrics.record(.resultLookup, started: ProcessInfo.processInfo.systemUptime, outcome: .timeout)
        metrics.record(.resultLookup, started: ProcessInfo.processInfo.systemUptime, outcome: .cancelled)
        let data = try JSONEncoder().encode(metrics.snapshot())
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("http") && !text.contains("token") && !text.contains("workspace"))
        let summary = try #require(metrics.snapshot()["resultLookup"])
        #expect(summary.requests == 3 && summary.successes == 1 && summary.failures == 1 && summary.cancellations == 1)
        #expect(summary.lastSuccessAt != nil)
        #expect(summary.lastHTTPStatus == nil)
    }

    private func imageData() throws -> Data {
        let pixels = Data(repeating: 140, count: 1200 * 900 * 4)
        let provider = try #require(CGDataProvider(data: pixels as CFData))
        let image = try #require(CGImage(width: 1200, height: 900, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 1200 * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let data = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return data as Data
    }

    @Test func concurrentImageViewsShareOneFetchAndCancellationDoesNotBreakOtherViewer() async throws {
        ResultImageCache.clear()
        defer { ResultImageCache.clear() }
        let data = try imageData()
        let (config, probe) = configure([.init(headers: ["Content-Length": String(data.count)], chunks: [data], delay: 0.1)])
        let first = Task { try await ResultImageCache.load(url, configuration: config) }
        let second = Task { try await ResultImageCache.load(url, configuration: config) }
        try await waitForRequest(probe)
        await Task.yield()
        first.cancel()
        _ = try await second.value
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(probe.requests == 1)
        _ = try await ResultImageCache.load(url, configuration: config)
        #expect(probe.requests == 1)
    }

    @Test func previewDownsamplesAndRejectsInvalidImages() async throws {
        let data = try imageData()
        let (config, _) = configure([.init(chunks: [data]), .init(chunks: [Data("not-image".utf8)])])
        let image = try await ResultImageCache.fetchThumbnail(url, configuration: config)
        #expect(image.width == 1100 && image.height <= 1100)
        await #expect(throws: ResultTransferError.invalidResponse) { try await ResultImageCache.fetchThumbnail(url, configuration: config) }
    }

    @Test func manualUpdateBypassesAutoCooldownButHonorsRequestAndServerLimits() async throws {
        let body = Data(#"{"tag_name":"v9.0.0","draft":false,"prerelease":false,"assets":[]}"#.utf8)
        let (config, probe) = configure([
            .init(chunks: [body]), .init(chunks: [body]), .init(status: 429, headers: ["Retry-After": "7200"]), .init(chunks: [body])
        ])
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let domain = "UpdateReliability-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        var clock: TimeInterval = 0
        let updates = AppUpdateStore(defaults: defaults, isAppStore: false, currentVersion: "0.4.3", session: session, uptime: { clock })
        await updates.check()
        clock = 60
        await updates.check()
        #expect(probe.requests == 1)
        await updates.check(manual: true)
        #expect(probe.requests == 2)
        clock = 61
        await updates.check(manual: true)
        #expect(probe.requests == 2 && updates.retryAt != nil)
        clock = 120
        await updates.check(manual: true)
        #expect(probe.requests == 3)
        clock = 7319
        await updates.check(manual: true)
        #expect(probe.requests == 3)
        clock = 7320
        await updates.check(manual: true)
        #expect(probe.requests == 4)
    }
}
