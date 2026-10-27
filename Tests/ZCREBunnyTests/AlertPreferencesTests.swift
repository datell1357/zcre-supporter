// 검증 분류: 작업 필터 · 자정 경계 · 조용한 기록 보존. 실제 서버/알림을 호출하지 않는다.
import Foundation
import Testing
import ZCRECore
@testable import ZCREBunny

@MainActor private func isolatedPreferences() -> (Preferences, UserDefaults, String) {
    let suite = "zcre.alert-policy.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    return (Preferences(defaults: defaults, domainName: suite), defaults, suite)
}

@Test @MainActor func focusScheduleHandlesBoundariesAndOvernight() {
    let (p,d,s) = isolatedPreferences(); defer { d.removePersistentDomain(forName: s) }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    func at(_ hour: Int, _ minute: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: hour, minute: minute))! }
    p.focusSchedule = true; p.focusStartMinute = 22 * 60; p.focusEndMinute = 8 * 60
    #expect(!p.isFocusActive(at: at(21,59), calendar: calendar))
    #expect(p.isFocusActive(at: at(22), calendar: calendar))
    #expect(p.isFocusActive(at: at(0), calendar: calendar))
    #expect(!p.isFocusActive(at: at(8), calendar: calendar))
    p.focusStartMinute = 9 * 60; p.focusEndMinute = 18 * 60
    #expect(p.isFocusActive(at: at(9), calendar: calendar))
    #expect(!p.isFocusActive(at: at(18), calendar: calendar))
    p.focusEndMinute = p.focusStartMinute
    #expect(p.isFocusActive(at: at(0), calendar: calendar))
    p.focusSchedule = false
    #expect(!p.isFocusActive(at: at(0), calendar: calendar))
    p.focusNow = true
    #expect(p.isFocusActive(at: at(0), calendar: calendar))
}

@Test @MainActor func jobCategoriesAreIndependentAndPersist() {
    let (p,d,s) = isolatedPreferences(); defer { d.removePersistentDomain(forName: s) }
    func job(_ model: String, _ media: String) -> GenerationJob { .init(id: "test", model: model, mediaType: media, status: .succeeded, createdAt: .now) }
    p.videoJobAlerts = false
    #expect(!p.allowsJobAlert(job("seedance-2", "video")))
    #expect(p.allowsJobAlert(job("bytedance-upscale-video", "video")))
    p.upscaleJobAlerts = false
    #expect(!p.allowsJobAlert(job("topaz-upscale-image", "image")))
    #expect(p.allowsJobAlert(job("gpt-image-2", "image")))
    p.audioJobAlerts = false; p.otherJobAlerts = false; p.focusNow = true
    #expect(!p.allowsJobAlert(job("test", "audio")))
    #expect(!p.allowsJobAlert(job("test", "unknown")))
    let restored = Preferences(defaults: d, domainName: s)
    #expect(!restored.videoJobAlerts && !restored.upscaleJobAlerts && restored.focusNow)
}

@Test @MainActor func filteredCompletedJobsRemainInHistory() {
    let (p,d,s) = isolatedPreferences(); defer { d.removePersistentDomain(forName: s) }
    p.videoJobAlerts = false; p.focusNow = true
    let job = GenerationJob(id: "quiet", model: "seedance-2", mediaType: "video", status: .succeeded, createdAt: .now)
    #expect(!p.allowsJobAlert(job) && p.isFocusActive())
    let history = AlertHistoryArchive.merging([], jobs: [job], clearedThrough: nil, demo: true)
    #expect(history.count == 1)
    #expect(history.first?.kind == .completed)
    p.focusNow = false; p.videoJobAlerts = true
    #expect(AlertHistoryArchive.merging(history, jobs: [job], clearedThrough: nil, demo: true) == history)
}
