// 기능 분류: 지크 모션 효과음 · 로컬 재생 · 중복 재생 방지
import AVFoundation
import Foundation

/// 실제 오디오 장치 없이 상태 전이를 검증할 수 있는 최소 재생 인터페이스다.
@MainActor
protocol PetSoundPlaying: AnyObject {
    /// 0–1 범위의 플레이어 음량을 적용한다.
    func setVolume(_ volume: Float)
    /// 반복 여부를 지정하고 재생 시작 성공 여부를 반환한다.
    @discardableResult func play(loop: Bool) -> Bool
    /// 현재 재생을 중단한다.
    func stop()
}

/// 번들에 있는 짧은 PCM 파일만 재생한다. 네트워크와 시스템 전체 음량은 사용하지 않는다.
@MainActor
private final class BundledPetSound: PetSoundPlaying {
    private let url: URL
    private var player: AVAudioPlayer?
    private var volume: Float = 0

    /// 리소스 경로만 준비한다. 실제 재생 시까지 오디오 장치를 열지 않는다.
    init?(name: String) {
        guard let url = Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Sounds") else { return nil }
        self.url = url
    }

    /// 이 효과음 플레이어의 음량만 변경한다.
    func setVolume(_ volume: Float) { self.volume = volume; player?.volume = volume }

    /// 재생할 때만 장치를 연다. 이 앱의 효과음은 모두 유한 재생이며 무한 루프를 사용하지 않는다.
    @discardableResult func play(loop: Bool) -> Bool {
        guard !loop, let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        self.player = player
        player.volume = volume
        player.currentTime = 0
        player.numberOfLoops = 0
        return player.play()
    }

    /// 재생을 멈추어 유휴 상태에서 오디오 장치를 계속 구동하지 않는다.
    func stop() { player?.stop(); player = nil }
}

/// 지크 컨트롤러 하나만 소리를 소유한다. 설정 미리보기·메뉴 아이콘에서 중복 재생하지 않는다.
@MainActor
final class PetSoundController {
    private struct State: Equatable {
        let motion: ZicMotion
        let audible: Bool
        let volume: Float
    }
    private let grab: (any PetSoundPlaying)?
    private let typing: (any PetSoundPlaying)?
    private var state: State?
    private var typingActive = false
    private var typingStarted: TimeInterval = 0
    private var nextTyping: TimeInterval = 0
    private var typingTask: Task<Void, Never>?
    private let otherAudio: (Bool) -> Bool
    private let uptime: () -> TimeInterval
    private let automaticTicks: Bool

    /// 앱에 포함된 홍보영상 효과음 두 개를 로드한다.
    convenience init() {
        self.init(grab: BundledPetSound(name: "grab"), typing: BundledPetSound(name: "typing"))
    }

    /// 테스트에서는 실제 소리를 내지 않는 재생 대역을 주입한다.
    init(grab: (any PetSoundPlaying)?, typing: (any PetSoundPlaying)?,
         otherAudio: @escaping (Bool) -> Bool = OtherAudioActivity.isActive,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, automaticTicks: Bool = true) {
        self.grab = grab
        self.typing = typing
        self.otherAudio = otherAudio; self.uptime = uptime; self.automaticTicks = automaticTicks
    }

    /// 드래그는 한 번, 타자는 짧은 구간만 재생한다. 다른 앱의 오디오를 감지하면 즉시 양보한다.
    func update(motion: ZicMotion, enabled: Bool, visible: Bool, sleeping: Bool, volume: Double) {
        let level = Float(volume.isFinite ? min(1, max(0, volume)) : 0)
        let next = State(motion: motion, audible: enabled && visible && !sleeping && level > 0, volume: level)
        guard next != state else { return }
        let enteringDrag = motion == .drag && state?.motion != .drag
        let wasWorking = state?.motion == .working && state?.audible == true
        state = next
        guard next.audible else { stopPlayback(); return }
        grab?.setVolume(level)
        typing?.setVolume(level)
        if motion != .drag { grab?.stop() }
        if enteringDrag { grab?.play(loop: false) }
        if motion == .working {
            if !wasWorking { nextTyping = uptime() }
            checkTyping()
        } else { stopTyping() }
    }

    /// 약 1초 재생 후 5초 쉬며 장치를 해제한다. 재생 중에는 0.5초 간격으로 다른 소리를 확인한다.
    func checkTyping() {
        typingTask?.cancel(); typingTask = nil
        guard state?.motion == .working, state?.audible == true else { stopTyping(); return }
        let now = uptime()
        if typingActive {
            if now - typingStarted >= 1 || otherAudio(true) {
                typing?.stop(); typingActive = false
                nextTyping = max(nextTyping, now + 2)
            }
        } else if now >= nextTyping {
            if otherAudio(false) { nextTyping = now + 2 }
            else {
                typingActive = typing?.play(loop: false) ?? false
                typingStarted = now
                nextTyping = now + 6
            }
        }
        guard automaticTicks else { return }
        let delay = typingActive ? 0.5 : max(0.5, nextTyping - now)
        typingTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.checkTyping()
        }
    }

    /// 대기 작업까지 취소해 숨김·실패·완료·잠자기 후 효과음이 다시 시작되지 않게 한다.
    private func stopTyping() {
        typingTask?.cancel(); typingTask = nil
        if typingActive { typing?.stop() }
        typingActive = false
    }

    /// 앱 종료 시 두 플레이어와 마지막 상태를 정리한다.
    func stop() {
        stopPlayback()
        state = nil
    }

    /// 숨김·잠자기·음소거·0% 음량에서는 반복 소리와 단발 소리를 모두 중단한다.
    private func stopPlayback() {
        grab?.stop()
        stopTyping()
    }
}
