// 기능 분류: 다른 앱의 오디오 우선권. 오디오 내용·앱 이름·기기 설정은 읽거나 기록하지 않는다.
import CoreAudio
import Foundation

enum OtherAudioActivity {
    /// CoreAudio의 실행 여부만 읽는다. 캡처·탭·마이크 권한 요청이나 장치 설정 변경은 없다.
    static func isActive(ownSoundPlaying: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        if AudioObjectHasProperty(system, &address) {
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
                  size % UInt32(MemoryLayout<AudioObjectID>.size) == 0, size <= 65_536 else { return true }
            if size == 0 { return false }
            var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
            let result = objects.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!) }
            guard result == noErr else { return true }
            for object in objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size) {
                guard let pid = integer(object, kAudioProcessPropertyPID) else { return true }
                if pid == UInt32(bitPattern: ProcessInfo.processInfo.processIdentifier) { continue }
                // 음악·영상뿐 아니라 통화/녹음 중에도 배경 타자음이 방해하지 않도록 양보한다.
                guard let output = integer(object, kAudioProcessPropertyIsRunningOutput),
                      let input = integer(object, kAudioProcessPropertyIsRunningInput) else { return true }
                if output != 0 || input != 0 { return true }
            }
            return false
        }
        // 구형 macOS는 앱별 구분이 없으므로 조용한 구간에서 장치의 사용 여부만 확인한다.
        // 자신의 짧은 재생도 0.5초 안에 양보하는 보수적인 경로를 사용한다.
        if ownSoundPlaying { return true }
        guard let device = integer(system, kAudioHardwarePropertyDefaultOutputDevice), device != 0,
              let running = integer(device, kAudioDevicePropertyDeviceIsRunningSomewhere) else { return true }
        return running != 0
    }

    /// 고정 크기 정수 속성만 읽으며 실패를 오디오 없음으로 추정하지 않는다.
    private static func integer(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              size == MemoryLayout<UInt32>.size else { return nil }
        return value
    }
}
