// 기능 분류: 스냅샷 간 상태 전이 · 알림 중복 방지 · 조회 간격
import Foundation

public enum MonitorEvent: Equatable, Sendable {
    case completed(GenerationJob)
    case failed(GenerationJob)
    case lowCredits(Decimal)
}

/// 첫 성공 조회로 기준선을 만들어 기존 완료 이력이 새 알림을 쏟아내지 않게 한다.
public struct Monitor: Sendable {
    private var workspaceKey: String?
    private var baselineFetch: Date?
    private var known: [String: GenerationJob] = [:]
    private var alertedIDs: [String] = []
    private var wasLow = false
    /// 계정별 작업 감시 기준선을 비어 있는 상태로 시작한다.
    public init() {}
    public var trackedActiveIDs: [String] { known.values.filter { $0.status.isActive || $0.status == .unknown }.map(\.id).sorted() }
    /// 계정 변경 시 이전 작업과 알림 기준선을 모두 초기화한다.
    public mutating func reset() { self = Monitor() }

    /// 첫 조회는 기준선으로 삼고 이후 완료·실패·잔액 임계치 진입만 이벤트로 만든다.
    public mutating func ingest(_ snapshot: WorkspaceSnapshot, lowCreditThreshold: Decimal) -> [MonitorEvent] {
        if workspaceKey != snapshot.workspaceKey { reset(); workspaceKey = snapshot.workspaceKey }
        var events: [MonitorEvent] = []
        let isLow = snapshot.balanceIsStale ? wasLow : snapshot.balance.available <= lowCreditThreshold
        if let baselineFetch {
            for job in snapshot.jobs where job.status == .succeeded || job.status == .failed {
                let prior = known[job.id]
                let justFinished = prior.map { !$0.status.isTerminal } ?? (job.createdAt >= baselineFetch)
                if justFinished && !alertedIDs.contains(job.id) {
                    events.append(job.status == .succeeded ? .completed(job) : .failed(job))
                    alertedIDs.append(job.id)
                }
            }
            if isLow && !wasLow { events.append(.lowCredits(snapshot.balance.available)) }
        }
        // 최신 이력 페이지 밖으로 밀려나도 미완료 작업은 추적 목록에 유지한다.
        var next = known.filter { $0.value.status.isActive || $0.value.status == .unknown }
        for job in snapshot.jobs { next[job.id] = job }
        known = next
        alertedIDs = Array(alertedIDs.suffix(1024))
        wasLow = isLow
        if baselineFetch == nil { baselineFetch = snapshot.fetchedAt }
        return events
    }
}

public enum PollPolicy {
    /// 정상 조회 간격은 작업 유무와 관계없이 5초이며 실패 시 최대 300초까지 지연한다.
    public static func delay(activeJobs: Int, failures: Int) -> TimeInterval {
        if failures > 0 { return min(300, 15 * pow(2, Double(min(failures, 5)))) }
        return 5
    }
}

public enum DemoWorkspace {
    /// 서버 호출 없는 화면 확인용 예시 작업과 잔액을 만든다.
    public static func snapshot(step: Int = 0, now: Date = .now) -> WorkspaceSnapshot {
        WorkspaceSnapshot(workspaceKey: "demo", workspaceName: "미리보기 워크스페이스", balance: CreditBalance(total: 1280, reserved: step == 0 ? 120 : 40, available: step == 0 ? 1160 : 1240), jobs: [
            GenerationJob(id: "demo-video", model: "seedance-2.5", mediaType: "video", status: step == 0 ? .running : .succeeded, createdAt: now.addingTimeInterval(-160)),
            GenerationJob(id: "demo-image", model: "gpt-image-2", mediaType: "image", status: .queued, createdAt: now.addingTimeInterval(-90)),
            GenerationJob(id: "demo-upscale", model: "bytedance-upscale-video", mediaType: "video", status: .succeeded, createdAt: now.addingTimeInterval(-500))
        ], fetchedAt: now)
    }
}
