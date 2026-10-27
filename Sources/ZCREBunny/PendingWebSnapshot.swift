// 기능 분류: WebKit 응답 대기 · 타임아웃 · 단일 완료
import Foundation
import ZCRECore

/// 페이지 이동이나 프로세스 중단으로 JavaScript 완료 콜백이 오지 않을 수 있다.
/// 네이티브 제한 시간으로 폴링 대기를 해제하고 늦은 콜백은 무시한다.
@MainActor
final class PendingWebSnapshot {
    private var continuation: CheckedContinuation<String, any Error>?
    private var outcome: Result<String, any Error>?
    private var deadline: Task<Void, Never>?

    /// 웹 응답을 비동기로 기다리되 응답이 사라져도 제한 시간 후 대기를 해제한다.
    func value(timeout: Duration = .seconds(25), start: () -> Void) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            if let outcome { continuation.resume(with: outcome); return }
            self.continuation = continuation
            deadline = Task { [weak self] in
                do { try await Task.sleep(for: timeout) } catch { return }
                self?.finish(.failure(SnapshotError.network))
            }
            start()
        }
    }
    /// 취소·타임아웃·정상 응답 중 먼저 도착한 결과로 한 번만 완료하고 나머지는 무시한다.
    func finish(_ result: Result<String, any Error>) {
        guard outcome == nil else { return }
        outcome = result
        deadline?.cancel(); deadline = nil
        continuation?.resume(with: result); continuation = nil
    }
}
