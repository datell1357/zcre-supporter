// 기능 분류: 유휴 인사 간격 · 산책 중 연기 · 작업/숨김 후 재예약
import Foundation

public struct IdleWaveSchedule {
    public private(set) var dueAt: TimeInterval?
    public init() {}

    /// 산책 중에는 마감 시각을 보존해 인사가 영원히 밀리지 않게 한다.
    /// 작업·숨김·잠자기 등으로 허용되지 않으면 누적 예약을 지운다.
    public mutating func delay(at now: TimeInterval, allowed: Bool, idle: Bool, randomUnit: Double) -> TimeInterval? {
        guard allowed else { dueAt = nil; return nil }
        if dueAt == nil { finished(at: now, randomUnit: randomUnit) }
        guard idle else { return nil }
        return max(0, (dueAt ?? now) - now)
    }

    /// 재생이 끝난 뒤 새 45~90초 간격을 선택한다. 날짜 변경과 무관한 단조 시계를 사용한다.
    public mutating func finished(at now: TimeInterval, randomUnit: Double) {
        let unit = randomUnit.isFinite ? min(1, max(0, randomUnit)) : 0.5
        dueAt = now + 45 + 45 * unit
    }
}
