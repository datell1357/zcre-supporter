// 검증 분류: 실제 오디오 출력 없이 붙잡힘·작업 소리의 수명과 설정 반영을 검증한다.
import Foundation
import Testing
@testable import ZCREBunny

@MainActor
private final class SilentPlayer: PetSoundPlaying {
    var plays: [Bool] = []
    var stops = 0
    var volume: Float = -1
    /// 마지막 적용 음량을 기록한다.
    func setVolume(_ volume: Float) { self.volume = volume }
    /// 소리는 내지 않고 반복 여부를 기록한다.
    func play(loop: Bool) -> Bool { plays.append(loop); return true }
    /// 중단 요청 횟수를 기록한다.
    func stop() { stops += 1 }
}

// 드래그 중 갱신과 음량 변경이 붙잡힘 소리를 반복해서 재생하지 않는지 확인한다.
@Test @MainActor func grabPlaysOncePerDragAndNeverFromIdleUpdates() {
    let grab = SilentPlayer(), typing = SilentPlayer()
    let sound = PetSoundController(grab: grab, typing: typing, otherAudio: { _ in false }, automaticTicks: false)
    sound.update(motion: .idle, enabled: true, visible: true, sleeping: false, volume: 0.35)
    #expect(grab.plays.isEmpty)
    for _ in 0..<20 {
        sound.update(motion: .drag, enabled: true, visible: true, sleeping: false, volume: 0.35)
    }
    sound.update(motion: .drag, enabled: true, visible: true, sleeping: false, volume: 0.8)
    #expect(grab.plays == [false])
    #expect(grab.volume == 0.8)
    sound.update(motion: .idle, enabled: true, visible: true, sleeping: false, volume: 0.8)
    sound.update(motion: .drag, enabled: true, visible: true, sleeping: false, volume: 0.8)
    #expect(grab.plays == [false, false])
    #expect(typing.plays.isEmpty)
}

// 작업 진입에서 유한 재생을 시작하고 드래그·완료 중 중단한 뒤 작업 복귀 시 재개한다.
@Test @MainActor func typingFollowsVisibleWorkingMotionAndStopsAtCompletion() {
    let grab = SilentPlayer(), typing = SilentPlayer()
    let sound = PetSoundController(grab: grab, typing: typing, otherAudio: { _ in false }, automaticTicks: false)
    for _ in 0..<20 {
        sound.update(motion: .working, enabled: true, visible: true, sleeping: false, volume: 0.35)
    }
    #expect(typing.plays == [false])
    sound.update(motion: .drag, enabled: true, visible: true, sleeping: false, volume: 0.35)
    #expect(typing.stops == 1)
    sound.update(motion: .working, enabled: true, visible: true, sleeping: false, volume: 0.35)
    #expect(typing.plays == [false, false])
    sound.update(motion: .complete, enabled: true, visible: true, sleeping: false, volume: 0.35)
    #expect(typing.stops == 2)
    sound.update(motion: .idle, enabled: true, visible: true, sleeping: false, volume: 0.35)
    #expect(typing.plays == [false, false])
}

// 숨김·잠자기·음소거·0%·비정상 음량에서 오디오 엔진을 계속 돌리지 않는지 확인한다.
@Test @MainActor func hiddenSleepingAndMutedPetStopsAllSound() {
    for (enabled, visible, sleeping, volume) in [(false, true, false, 0.35), (true, false, false, 0.35),
                                               (true, true, true, 0.35), (true, true, false, 0),
                                               (true, true, false, Double.nan)] {
        let grab = SilentPlayer(), typing = SilentPlayer()
        let sound = PetSoundController(grab: grab, typing: typing, otherAudio: { _ in false }, automaticTicks: false)
        sound.update(motion: .working, enabled: true, visible: true, sleeping: false, volume: 0.35)
        sound.update(motion: .working, enabled: enabled, visible: visible, sleeping: sleeping, volume: volume)
        #expect(typing.stops == 1)
        #expect(grab.stops > 0)
        #expect(typing.plays == [false])
        sound.update(motion: .working, enabled: true, visible: true, sleeping: false, volume: 0.35)
        #expect(typing.plays == [false, false])
    }
}

// 음량은 재생을 처음부터 다시 시작하지 않고 즉시 반영되며 음소거 해제는 새 드래그가 아니다.
@Test @MainActor func volumeChangesDoNotRestartLoopsOrReplayGrabOnUnmute() {
    let grab = SilentPlayer(), typing = SilentPlayer()
    let sound = PetSoundController(grab: grab, typing: typing, otherAudio: { _ in false }, automaticTicks: false)
    sound.update(motion: .working, enabled: true, visible: true, sleeping: false, volume: 0.35)
    sound.update(motion: .working, enabled: true, visible: true, sleeping: false, volume: 2)
    #expect(typing.plays == [false])
    #expect(typing.volume == 1)
    sound.update(motion: .drag, enabled: false, visible: true, sleeping: false, volume: 0.35)
    sound.update(motion: .drag, enabled: true, visible: true, sleeping: false, volume: 0.35)
    #expect(grab.plays.isEmpty)
    sound.stop()
    #expect(typing.stops == 1)
}

// 타자음은 약 1초 뒤 멈추고 정해진 휴지기 전에는 다시 장치를 사용하지 않는다.
@Test @MainActor func typingUsesShortBurstsAndReleasesBetweenThem() {
    let grab = SilentPlayer(), typing = SilentPlayer()
    var now = 0.0
    let sound = PetSoundController(grab: grab, typing: typing, otherAudio: { _ in false }, uptime: { now }, automaticTicks: false)
    sound.update(motion: .working, enabled: true, visible: true, sleeping: false, volume: 0.35)
    #expect(typing.plays == [false])
    now = 1
    sound.checkTyping()
    #expect(typing.stops == 1)
    now = 5
    sound.checkTyping()
    #expect(typing.plays == [false])
    now = 6
    sound.checkTyping()
    #expect(typing.plays == [false,false])
    sound.update(motion: .cry, enabled: true, visible: true, sleeping: false, volume: 0.35)
    #expect(typing.stops == 2)
    now = 20
    sound.checkTyping()
    #expect(typing.plays == [false,false])
}

// 다른 앱이 먼저 재생하거나 재생 도중 시작하면 타자음을 양보하고 조용해진 뒤에만 복귀한다.
@Test @MainActor func typingYieldsToOtherAudioWithoutChangingItsSettings() {
    let grab = SilentPlayer(), typing = SilentPlayer()
    var now = 0.0, otherActive = true
    let sound = PetSoundController(grab: grab, typing: typing, otherAudio: { _ in otherActive }, uptime: { now }, automaticTicks: false)
    sound.update(motion: .working, enabled: true, visible: true, sleeping: false, volume: 0.35)
    #expect(typing.plays.isEmpty)
    otherActive = false; now = 2
    sound.checkTyping()
    #expect(typing.plays == [false])
    otherActive = true; now = 2.5
    sound.checkTyping()
    #expect(typing.stops == 1)
    now = 8
    sound.checkTyping()
    #expect(typing.plays == [false])
    otherActive = false; now = 10
    sound.checkTyping()
    #expect(typing.plays == [false,false])
    sound.stop()
    now = 30
    sound.checkTyping()
    #expect(typing.plays == [false,false])
}

// 소리 설정은 기존 알림 소리와 별도로 저장하고 다시 실행해도 유지한다.
@Test @MainActor func petSoundSettingsPersistIndependentlyOfNotifications() throws {
    let domain = "zcre-pet-sound-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = Preferences(defaults: defaults, domainName: domain)
    #expect(preferences.petSounds)
    #expect(preferences.petSoundVolume == 0.35)
    #expect(!preferences.sound)
    preferences.petSounds = false
    preferences.petSoundVolume = 0.21
    preferences.sound = true
    let restored = Preferences(defaults: defaults, domainName: domain)
    #expect(!restored.petSounds)
    #expect(restored.petSoundVolume == 0.21)
    #expect(restored.sound)
}
