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
    func outputs(for requestID: String, workspace: String) async throws -> [JobOutput] {
        let key = workspace + ":" + requestID
        if let hit = outputCache[key], hit.until > .now { return hit.outputs }
        guard Date.now >= outputsRetryAt, isLoaded,
              let sourceURL = Bundle.module.url(forResource: "ReadOutputs", withExtension: "js") else { throw SnapshotError.network }
        outputsRetryAt = .now.addingTimeInterval(5)
        let generation = outputGeneration
        let script = try String(contentsOf: sourceURL, encoding: .utf8)
        let value = try await webView.callAsyncJavaScript(script, arguments: ["requestID": requestID, "workspaceKey": workspace], in: nil, contentWorld: .page)
        try Task.checkCancellation()
        guard outputGeneration == generation else { throw SnapshotError.accountChanged }
        guard let json = value as? String, let data = json.data(using: .utf8) else { throw SnapshotError.invalidResponse }
        let payload = try JSONDecoder().decode(JobOutputsPayload.self, from: data)
        if let code = payload.error {
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
        return outputs
    }

    /// 로그아웃·계정 전환 시 결과 캐시와 진행 중 조회를 폐기한다.
    func clearOutputs() {
        ResultImageCache.cache.removeAllObjects()
        outputGeneration += 1
        outputCache.removeAll(); outputsRetryAt = .distantPast
        webView.evaluateJavaScript("window.__zcreSupporterOutputAbort?.abort()", completionHandler: nil)
    }
}
