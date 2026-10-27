import Testing
@testable import ZCRECore

// 짧은 산책을 반복해도 인사가 영원히 연기되지 않으며 멈춘 순간 예약을 이어간다.
@Test func idleGreetingWaitsThroughWalkWithoutRestartingCountdown() {
    var schedule = IdleWaveSchedule()
    #expect(schedule.delay(at: 100, allowed: true, idle: true, randomUnit: 0) == 45)
    for time in [110.0, 120, 130, 140, 150] {
        #expect(schedule.delay(at: time, allowed: true, idle: false, randomUnit: 1) == nil)
        #expect(schedule.dueAt == 145)
    }
    #expect(schedule.delay(at: 152, allowed: true, idle: true, randomUnit: 1) == 0)
    schedule.finished(at: 156, randomUnit: 1)
    #expect(schedule.delay(at: 157, allowed: true, idle: true, randomUnit: 0) == 89)
}

// 작업·숨김·잠자기 후에는 밀린 인사를 즉시 몰아서 하지 않고 새 간격을 둔다.
@Test func idleGreetingStartsFreshAfterBeingDisallowed() {
    var schedule = IdleWaveSchedule()
    _ = schedule.delay(at: 0, allowed: true, idle: true, randomUnit: 0)
    #expect(schedule.delay(at: 44, allowed: false, idle: false, randomUnit: 0) == nil)
    #expect(schedule.dueAt == nil)
    #expect(schedule.delay(at: 1000, allowed: true, idle: true, randomUnit: 0.5) == 67.5)
}
