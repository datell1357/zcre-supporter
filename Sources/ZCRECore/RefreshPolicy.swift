// 기능 분류: 단일 계정 조회 일정 · 공개 상태 캐시와 오류 재시도
import Foundation

public struct AccountPollSchedule: Sendable {
    public private(set) var nextUptime: TimeInterval = 0
    public init() {}

    /// 새 연결·깨우기는 1초 이내로 분산하되 서버의 Retry-After는 호출자가 별도로 유지한다.
    public mutating func resume(at now: TimeInterval, jitter: Double) {
        nextUptime = now + min(1, max(0, jitter))
    }

    /// 수동 갱신도 동일한 시작 간격을 사용해 정상 폴링과 중복하지 않는다.
    public mutating func started(at now: TimeInterval) { nextUptime = now + 5 }

    /// 느린 요청을 중첩하지 않고 오류 복귀 시점을 분산한다. 정상 5초 주기는 유지한다.
    public mutating func finished(started: TimeInterval, at now: TimeInterval, failures: Int, signedOut: Bool, jitter: Double) {
        let base = signedOut ? 15 : PollPolicy.delay(activeJobs: 0, failures: failures)
        let interval = failures > 0 && !signedOut ? min(300, base * (1 + min(1, max(0, jitter)) * 0.2)) : base
        nextUptime = max(now + 1, started + interval)
    }
}

public struct PublicStatusSchedule: Sendable {
    public private(set) var lastAttempt: TimeInterval?
    public private(set) var lastSuccess: TimeInterval?
    public private(set) var retryUptime: TimeInterval = 0
    public private(set) var failures = 0
    public init() {}

    /// 일반 조회는 성공 후 60초, 명시적 새로고침도 최소 5초와 서버 대기를 지킨다.
    public func nextUptime(manual: Bool) -> TimeInterval {
        max((lastAttempt ?? -5) + 5, retryUptime, manual ? 0 : (lastSuccess ?? -60) + 60)
    }

    /// 요청을 시작한 시각을 먼저 기록해 취소·재개방으로 간격 제한을 우회하지 못하게 한다.
    public mutating func begin(at now: TimeInterval, manual: Bool) -> Bool {
        guard now >= nextUptime(manual: manual) else { return false }
        lastAttempt = now
        return true
    }

    /// 성공 또는 유효한 304 응답에서만 캐시의 확인 시각과 오류 횟수를 갱신한다.
    public mutating func succeeded(at now: TimeInterval) {
        lastSuccess = now; failures = 0; retryUptime = 0
    }

    /// 30초부터 최대 300초까지 지수 지연하며 Retry-After가 더 길면 해당 시각까지 기다린다.
    public mutating func failed(at now: TimeInterval, retryAfter: TimeInterval, jitter: Double) {
        failures = min(5, failures + 1)
        let delay = min(300, 15 * pow(2, Double(failures)) * (1 + min(1, max(0, jitter)) * 0.2))
        retryUptime = now + max(delay, retryAfter.isFinite ? max(0, retryAfter) : 0)
    }
}

public enum HTTPRetryAfter {
    /// 초 단위 또는 HTTP 날짜 형식의 서버 대기를 해석하며 잘못된 값은 무시한다.
    public static func seconds(_ value: String?, relativeTo now: Date) -> TimeInterval {
        guard let value else { return 0 }
        if let seconds = Double(value), seconds.isFinite { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        guard let date = formatter.date(from: value) else { return 0 }
        return max(0, date.timeIntervalSince(now))
    }
}
