// 기능 분류: 이미지 청크 수신 · 12MiB 제한 · 작은 미리보기 디코딩 · 동시 요청 병합
import AppKit
import ImageIO

@MainActor enum ResultImageCache {
    static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.totalCostLimit = 24 * 1024 * 1024; cache.countLimit = 12
        return cache
    }()
    private struct InFlight {
        let task: Task<CGImage, Error>
        var waiters: Set<UUID>
    }
    private static var inFlight: [URL: InFlight] = [:]

    static func load(_ url: URL, configuration: URLSessionConfiguration = .ephemeral) async throws -> NSImage {
        try Task.checkCancellation()
        if let image = cache.object(forKey: url as NSURL) { return image }
        let waiter = UUID()
        let task: Task<CGImage, Error>
        if var entry = inFlight[url] {
            entry.waiters.insert(waiter); inFlight[url] = entry; task = entry.task
        } else {
            task = Task.detached(priority: .utility) { try await fetchThumbnail(url, configuration: configuration) }
            inFlight[url] = InFlight(task: task, waiters: [waiter])
        }
        defer { release(url, waiter: waiter) }
        return try await withTaskCancellationHandler {
            let thumbnail = try await task.value
            try Task.checkCancellation()
            guard inFlight[url]?.waiters.contains(waiter) == true else { throw CancellationError() }
            let image = NSImage(cgImage: thumbnail, size: .zero)
            cache.setObject(image, forKey: url as NSURL, cost: thumbnail.bytesPerRow * thumbnail.height)
            return image
        } onCancel: {
            Task { @MainActor in release(url, waiter: waiter) }
        }
    }
    private static func release(_ url: URL, waiter: UUID) {
        guard var entry = inFlight[url], entry.waiters.remove(waiter) != nil else { return }
        if entry.waiters.isEmpty { entry.task.cancel(); inFlight.removeValue(forKey: url) }
        else { inFlight[url] = entry }
    }
    static func clear() {
        cache.removeAllObjects()
        for entry in inFlight.values { entry.task.cancel() }
        inFlight.removeAll()
    }

    /// 바이트별 배열 확장 대신 청크를 임시 파일에 쓰고 메인 액터 밖에서 최대 1100px로 디코딩한다.
    nonisolated static func fetchThumbnail(_ url: URL, configuration: URLSessionConfiguration = .ephemeral) async throws -> CGImage {
        let started = ProcessInfo.processInfo.systemUptime
        var outcome = DiagnosticOutcome.invalidResponse
        var status: Int?
        defer { DiagnosticMetrics.shared.record(.resultPreview, started: started, outcome: outcome, status: status) }
        do {
            let file = try await ResultTransfer(configuration: configuration, limit: 12 * 1024 * 1024).fetch(url)
            defer { ResultTransfer.removeTemporary(file) }
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1100,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else { throw ResultTransferError.invalidResponse }
            try Task.checkCancellation()
            outcome = .success; status = 200
            return thumbnail
        } catch { outcome = DiagnosticOutcome.failure(error); status = DiagnosticOutcome.httpStatus(error); throw error }
    }
}
