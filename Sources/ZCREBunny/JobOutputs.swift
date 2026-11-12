// 기능 분류: 결과 메타데이터 검증 · 안전한 웹 연결 · 요청 시점 조회
import Foundation
import ZCRECore

struct JobOutput: Decodable, Identifiable {
    let id: String
    let mediaType: String?
    let contentType: String?
    let url: String
    let originalURL: String?
    let expires: Double?

    /// 서버 결과도 HTTPS URL만 허용한다. 서명 주소는 디스크·로그에 저장하지 않는다.
    static func safeURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              host != "localhost", !host.hasSuffix(".local"),
              !host.contains(":"), host.range(of: #"^\d+\.\d+\.\d+\.\d+$"#, options: .regularExpression) == nil else { return nil }
        return url
    }
    var previewURL: URL? { Self.safeURL(url) }
    var downloadURL: URL? { Self.safeURL(originalURL) ?? previewURL }
    var kind: String {
        if contentType?.hasPrefix("video/") == true { return "video" }
        if contentType?.hasPrefix("audio/") == true { return "audio" }
        if contentType?.hasPrefix("image/") == true { return "image" }
        return mediaType ?? "unknown"
    }
    var fileExtension: String {
        switch contentType?.split(separator: ";").first {
        case "image/png": "png"
        case "image/jpeg": "jpg"
        case "image/webp": "webp"
        case "video/webm": "webm"
        case "audio/mpeg": "mp3"
        case "audio/wav", "audio/x-wav": "wav"
        case "audio/mp4": "m4a"
        case "video/mp4": "mp4"
        default: "bin"
        }
    }
}

struct JobOutputsPayload: Decodable {
    let outputs: [JobOutput]?
    let error: Int?
    let retryAfter: String?
}

enum JobResultLink {
    /// 웹에서 사용하는 작업별 결과 경로와 오디오 스튜디오 경로를 재사용한다.
    static func url(for job: GenerationJob) -> URL {
        var url = URLComponents(string: "https://www.zcre.co.kr")!
        if job.mediaType == "audio" {
            url.path = "/studio/audio"; url.queryItems = [URLQueryItem(name: "j", value: job.id)]
        } else { url.path = "/results/\(job.id)" }
        return url.url!
    }
}

extension WebSession {
    /// 결과창을 열 때 한 번만 GET한다. 계정별 30초 메모리 캐시로 반복 열기 요청을 줄인다.
    func outputs(for requestID: String, workspace: String, forceRefresh: Bool = false) async throws -> [JobOutput] {
        let key = workspace + ":" + requestID
        if !forceRefresh, let hit = outputCache[key], hit.until > .now { return hit.outputs }
        if Date.now < outputsRetryAt {
            let wait = outputsRetryAt.timeIntervalSinceNow
            guard forceRefresh, wait <= 5 else { throw SnapshotError.network }
            try await Task.sleep(for: .seconds(wait))
        }
        try Task.checkCancellation()
        guard isLoaded,
              let sourceURL = Bundle.module.url(forResource: "ReadOutputs", withExtension: "js") else { throw SnapshotError.network }
        outputsRetryAt = .now.addingTimeInterval(5)
        let generation = outputGeneration
        let script = try String(contentsOf: sourceURL, encoding: .utf8)
        let started = ProcessInfo.processInfo.systemUptime
        var outcome = DiagnosticOutcome.invalidResponse
        var status: Int?
        defer { DiagnosticMetrics.shared.record(.resultLookup, started: started, outcome: outcome, status: status) }
        let pending = PendingWebSnapshot()
        pendingOutputs?.finish(.failure(CancellationError()))
        pendingOutputs = pending
        defer { if pendingOutputs === pending { pendingOutputs = nil } }
        let json: String
        do {
            json = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await pending.value(timeoutError: URLError(.timedOut)) {
                    webView.callAsyncJavaScript(script, arguments: ["requestID": requestID, "workspaceKey": workspace], in: nil, in: .page) { result in
                        pending.finish(result.flatMap { value in
                            guard let json = value as? String else { return .failure(SnapshotError.invalidResponse) }
                            return .success(json)
                        })
                    }
                }
            } onCancel: {
                Task { @MainActor in
                    if self.pendingOutputs === pending { self.cancelOutputs() }
                    else { pending.finish(.failure(CancellationError())) }
                }
            }
        } catch {
            outcome = DiagnosticOutcome.failure(error)
            if pendingOutputs === pending { cancelOutputs() }
            throw error
        }
        try Task.checkCancellation()
        guard outputGeneration == generation else { throw SnapshotError.accountChanged }
        guard let data = json.data(using: .utf8), data.count <= 262_144 else { throw SnapshotError.invalidResponse }
        let payload = try JSONDecoder().decode(JobOutputsPayload.self, from: data)
        if let code = payload.error {
            status = code; outcome = .httpError
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            let seconds = Double(payload.retryAfter ?? "") ?? payload.retryAfter.flatMap { formatter.date(from: $0)?.timeIntervalSinceNow } ?? 60
            outputsRetryAt = .now.addingTimeInterval(min(86400, max(5, seconds)))
            throw SnapshotError.http(code)
        }
        guard let outputs = payload.outputs, outputs.count <= 64,
              outputs.allSatisfy({ !$0.id.isEmpty && $0.previewURL != nil }) else { throw SnapshotError.invalidResponse }
        outputCache = outputCache.filter { $0.value.until > .now }
        if outputCache.count >= 20 { outputCache.removeAll() }
        let ttl = min(30, outputs.map { max(0, ($0.expires ?? 30) - 5) }.min() ?? 0)
        outputCache[key] = (.now.addingTimeInterval(ttl), outputs)
        outcome = .success; status = 200
        return outputs
    }

    /// 결과 조회만 취소한다. 다른 기능의 WebKit 요청은 유지한다.
    func cancelOutputs() {
        pendingOutputs?.finish(.failure(CancellationError()))
        webView.evaluateJavaScript("window.__zcreSupporterOutputAbort?.abort()", completionHandler: nil)
    }

    /// 로그아웃·계정 전환 시 결과 캐시와 진행 중 조회를 폐기한다.
    func clearOutputs() {
        ResultImageCache.clear()
        outputGeneration += 1
        outputCache.removeAll(); outputsRetryAt = .distantPast
        cancelOutputs()
    }
}
