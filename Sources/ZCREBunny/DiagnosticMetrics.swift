// 기능 분류: 고정된 기능·결과 코드만 메모리 집계. URL·오류 원문·사용자 정보는 받지 않는다.
import Foundation
import ZCRECore

enum DiagnosticOperation: String, Codable, CaseIterable, Sendable {
    case accountSnapshot, creatorMetrics, serviceStatus, updateCheck, resultLookup, resultPreview, resultDownload
}
enum DiagnosticOutcome: String, Codable, Sendable {
    case success, cancelled, timeout, httpError, invalidResponse, storageError, networkError
    static func failure(_ error: Error) -> Self {
        if let error = error as? SnapshotError {
            switch error {
            case .http: return .httpError
            case .invalidResponse, .unsupportedWorkspace: return .invalidResponse
            case .accountChanged: return .cancelled
            default: return .networkError
            }
        }
        if let transfer = error as? ResultTransferError {
            switch transfer {
            case .http: return .httpError
            case .insufficientSpace: return .storageError
            default: return .invalidResponse
            }
        }
        if error is CancellationError { return .cancelled }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            if ns.code == NSURLErrorCancelled { return .cancelled }
            if ns.code == NSURLErrorTimedOut { return .timeout }
        }
        if ns.domain == NSCocoaErrorDomain { return .storageError }
        return .networkError
    }
    static func httpStatus(_ error: Error) -> Int? {
        if case ResultTransferError.http(let code) = error { return code }
        if case SnapshotError.http(let code) = error { return code }
        return nil
    }
}
struct DiagnosticSummary: Codable, Sendable {
    var requests = 0
    var successes = 0
    var failures = 0
    var cancellations = 0
    var lastSuccessAt: Date?
    var lastDurationMilliseconds = 0
    var lastHTTPStatus: Int?
    var lastOutcome: DiagnosticOutcome?
}

/// 기능 수만큼의 집계만 보유한다. 호출자가 자유 문자열을 전달할 수 없고 자동 업로드·디스크 저장도 없다.
final class DiagnosticMetrics: @unchecked Sendable {
    static let shared = DiagnosticMetrics()
    private let lock = NSLock()
    private var entries: [DiagnosticOperation: DiagnosticSummary] = [:]
    func record(_ operation: DiagnosticOperation, started: TimeInterval, outcome: DiagnosticOutcome, status: Int? = nil) {
        lock.withLock {
            var value = entries[operation] ?? DiagnosticSummary()
            value.requests += 1
            switch outcome {
            case .success: value.successes += 1; value.lastSuccessAt = .now
            case .cancelled: value.cancellations += 1
            default: value.failures += 1
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            value.lastDurationMilliseconds = elapsed.isFinite ? Int(min(86_400_000, max(0, elapsed * 1000))) : 0
            value.lastHTTPStatus = status.flatMap { (100...599).contains($0) ? $0 : nil }
            value.lastOutcome = outcome
            entries[operation] = value
        }
    }
    func snapshot() -> [String: DiagnosticSummary] { lock.withLock { Dictionary(uniqueKeysWithValues: entries.map { ($0.key.rawValue, $0.value) }) } }
}
