// 검증 분류: 실제 대기·네트워크 없는 조회 간격, 재시도 및 시각 경계 회귀 검증
import Foundation
import Testing
@testable import ZCRECore

// 빠른 응답은 시작 기준 5초, 느린 응답은 완료 후 최소 1초의 여유를 지킨다.
@Test func accountScheduleKeepsFiveSecondsWithoutOverlappingSlowRequests() {
    var schedule = AccountPollSchedule()
    schedule.started(at: 100)
    #expect(schedule.nextUptime == 105)
    schedule.finished(started: 100, at: 100.2, failures: 0, signedOut: false, jitter: 1)
    #expect(schedule.nextUptime == 105)
    schedule.finished(started: 100, at: 110, failures: 0, signedOut: false, jitter: 0)
    #expect(schedule.nextUptime == 111)
}

// 오류 복귀를 분산하되 로그인 대기·최대 지연·정상 복귀의 기존 약속을 지킨다.
@Test func accountBackoffAndResumeRemainBounded() {
    var schedule = AccountPollSchedule()
    schedule.finished(started: 100, at: 101, failures: 1, signedOut: false, jitter: 1)
    #expect(schedule.nextUptime == 136)
    schedule.finished(started: 100, at: 101, failures: 999, signedOut: false, jitter: 1)
    #expect(schedule.nextUptime == 400)
    schedule.finished(started: 100, at: 101, failures: 5, signedOut: true, jitter: 1)
    #expect(schedule.nextUptime == 115)
    schedule.resume(at: 100, jitter: 2)
    #expect(schedule.nextUptime == 101)
    schedule.resume(at: 100, jitter: -1)
    #expect(schedule.nextUptime == 100)
}

// 창 재개방은 60초 캐시를, 명시적인 갱신은 최소 5초 제한을 공유한다.
@Test func statusCacheAndManualRefreshShareOneGate() {
    var schedule = PublicStatusSchedule()
    let initial = schedule.begin(at: 0, manual: false)
    let tooSoon = schedule.begin(at: 1, manual: true)
    #expect(initial && !tooSoon)
    schedule.succeeded(at: 2)
    #expect(schedule.nextUptime(manual: false) == 62)
    #expect(schedule.nextUptime(manual: true) == 5)
    let beforeExpiry = schedule.begin(at: 61, manual: false)
    let expired = schedule.begin(at: 62, manual: false)
    #expect(!beforeExpiry && expired)
}

// 수동 갱신·창 닫기/열기로 서버가 지정한 대기 시간을 우회하지 못한다.
@Test func serverRetryAfterSurvivesEveryStatusRefreshMode() {
    var schedule = PublicStatusSchedule()
    let initial = schedule.begin(at: 100, manual: false)
    #expect(initial)
    schedule.failed(at: 101, retryAfter: 600, jitter: 1)
    #expect(schedule.nextUptime(manual: true) == 701)
    #expect(schedule.nextUptime(manual: false) == 701)
    let beforeRetry = schedule.begin(at: 700, manual: true)
    let allowedRetry = schedule.begin(at: 701, manual: true)
    #expect(!beforeRetry && allowedRetry)
    schedule.succeeded(at: 702)
    #expect(schedule.failures == 0)
    #expect(schedule.nextUptime(manual: false) == 762)
}

// 서버 지연이 없는 실패도 30~300초로 제한하며 잘못된 숫자로 일정이 고장 나지 않는다.
@Test func statusFailureBackoffIsBounded() {
    var schedule = PublicStatusSchedule()
    schedule.failed(at: 0, retryAfter: .nan, jitter: 0)
    #expect(schedule.retryUptime == 30)
    for _ in 0..<10 { schedule.failed(at: 0, retryAfter: 0, jitter: 1) }
    #expect(schedule.retryUptime == 300)
    #expect(schedule.failures == 5)
}

// Retry-After의 초·HTTP 날짜·잘못된 값과 기한이 지난 값을 구분한다.
@Test func retryAfterParsesServerDatesAndRejectsInvalidNumbers() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(HTTPRetryAfter.seconds("120", relativeTo: now) == 120)
    #expect(HTTPRetryAfter.seconds("Tue, 14 Nov 2023 22:15:20 GMT", relativeTo: now) == 120)
    for value in [nil, "", "NaN", "Infinity", "-10", "invalid", "Tue, 14 Nov 2023 22:00:00 GMT"] {
        #expect(HTTPRetryAfter.seconds(value, relativeTo: now) == 0)
    }
}
