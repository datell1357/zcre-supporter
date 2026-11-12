// 기능 분류: 결과 파일 청크 수신 · 진행률 · 취소 · 같은 볼륨에서 안전한 최종 저장
import Foundation

enum ResultTransferError: Error, Equatable {
    case http(Int), tooLarge, truncated, insufficientSpace, invalidResponse
}
struct ResultTransferProgress: Sendable {
    let received: Int64
    let expected: Int64?
    var fraction: Double? { expected.flatMap { $0 > 0 ? min(1, Double(received) / Double($0)) : nil } }
}

/// URLSession 콜백과 Task 취소는 잠금으로 직렬화한다. 원본 영상 전체를 메모리에 쌓지 않는다.
final class ResultTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let configuration: URLSessionConfiguration
    private let limit: Int64?
    private let capacity: @Sendable (URL) -> Int64?
    private let progress: @Sendable (ResultTransferProgress) -> Void
    private let folder: URL
    private let file: URL
    private var handle: FileHandle?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<URL, Error>?
    private var finished = false
    private var cancelled = false
    private var received: Int64 = 0
    private var expected: Int64?
    private var lastReport: TimeInterval = 0

    init(configuration: URLSessionConfiguration = .ephemeral, limit: Int64? = nil,
         capacity: @escaping @Sendable (URL) -> Int64? = ResultTransfer.availableCapacity,
         progress: @escaping @Sendable (ResultTransferProgress) -> Void = { _ in }) {
        self.configuration = configuration; self.limit = limit; self.progress = progress; self.capacity = capacity
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ZCRE-transfer-\(UUID())", isDirectory: true)
        file = folder.appendingPathComponent("payload")
    }

    func fetch(_ url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                self.session = session
                var request = URLRequest(url: url); request.timeoutInterval = 60
                let task = session.dataTask(with: request)
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: { self.cancel() }
    }

    func cancel() {
        lock.withLock { cancelled = true }
        finish(.failure(CancellationError()))
    }

    /// 헤더와 실제 수신량을 모두 확인해 Content-Length가 없어도 용량 제한을 지킨다.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else { completionHandler(.cancel); finish(.failure(ResultTransferError.invalidResponse)); return }
        guard response.statusCode == 200 else { completionHandler(.cancel); finish(.failure(ResultTransferError.http(response.statusCode))); return }
        do {
            try lock.withLock {
                guard !finished else { throw CancellationError() }
                let length = response.expectedContentLength
                expected = length >= 0 ? length : nil
                if let limit, let expected, expected > limit { throw ResultTransferError.tooLarge }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                if let expected, let available = capacity(folder),
                   expected > max(0, available - 16 * 1024 * 1024) { throw ResultTransferError.insufficientSpace }
                guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
                handle = try FileHandle(forWritingTo: file)
            }
            progress(.init(received: 0, expected: expected))
            completionHandler(.allow)
        } catch { completionHandler(.cancel); finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            let update: ResultTransferProgress? = try lock.withLock {
                guard !finished else { return nil }
                if let limit, Int64(data.count) > limit - received { throw ResultTransferError.tooLarge }
                try handle?.write(contentsOf: data)
                received += Int64(data.count)
                let now = ProcessInfo.processInfo.systemUptime
                guard now - lastReport >= 0.2 else { return nil }
                lastReport = now
                return .init(received: received, expected: expected)
            }
            if let update { progress(update) }
        } catch { finish(.failure(error)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        let result: Result<URL, Error> = lock.withLock {
            if let expected, received != expected,
               (task.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Encoding") == nil { return .failure(ResultTransferError.truncated) }
            return handle == nil ? .failure(ResultTransferError.invalidResponse) : .success(file)
        }
        progress(.init(received: received, expected: expected))
        finish(result)
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = continuation; self.continuation = nil
        let session = session; self.session = nil; self.task = nil
        try? handle?.close(); handle = nil
        lock.unlock()
        session?.invalidateAndCancel()
        if case .failure = result { try? FileManager.default.removeItem(at: folder) }
        continuation?.resume(with: result)
    }

    /// 일부 샌드박스는 용량 속성을 0으로 반환한다. 알 수 없는 값은 쓰기 실패로 판단한다.
    private static func availableCapacity(_ folder: URL) -> Int64? {
        if let value = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage, value > 0 { return value }
        if let values = try? FileManager.default.attributesOfFileSystem(forPath: folder.path),
           let number = values[.systemFreeSize] as? NSNumber, number.int64Value > 0 { return number.int64Value }
        return nil
    }

    static func removeTemporary(_ file: URL) { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

    /// 먼저 저장 위치와 같은 볼륨에 완전한 파일을 복사한다. 실패한 수신으로 기존 결과를 덮지 않는다.
    static func save(_ source: URL, to destination: URL) throws {
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".zcre-save-\(UUID())")
        defer { try? FileManager.default.removeItem(at: staging) }
        try Task.checkCancellation()
        try FileManager.default.copyItem(at: source, to: staging)
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else { try FileManager.default.moveItem(at: staging, to: destination) }
    }
}

/// 만료 가능성이 있는 응답에서만 메타데이터를 한 번 갱신한다. 생성·결제 요청은 하지 않는다.
@MainActor enum ResultDownload {
    static func fetch(initial: URL, refreshedURL: () async throws -> URL,
                      transfer: (URL) async throws -> URL) async throws -> URL {
        do { return try await transfer(initial) }
        catch ResultTransferError.http(let status) where [401, 403, 404, 410].contains(status) {
            try Task.checkCancellation()
            let fresh = try await refreshedURL()
            try Task.checkCancellation()
            return try await transfer(fresh)
        }
    }
}
