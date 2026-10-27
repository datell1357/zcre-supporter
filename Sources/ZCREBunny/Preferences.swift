// 기능 분류: 로컬 사용자 설정 · 이전 버전 크기 마이그레이션
import Foundation
import Observation
import ZCRECore

@MainActor @Observable
final class Preferences {
    private let defaults: UserDefaults
    var imageJobAlerts: Bool { didSet { defaults.set(imageJobAlerts, forKey: "imageJobAlerts") } }
    var videoJobAlerts: Bool { didSet { defaults.set(videoJobAlerts, forKey: "videoJobAlerts") } }
    var upscaleJobAlerts: Bool { didSet { defaults.set(upscaleJobAlerts, forKey: "upscaleJobAlerts") } }
    var audioJobAlerts: Bool { didSet { defaults.set(audioJobAlerts, forKey: "audioJobAlerts") } }
    var otherJobAlerts: Bool { didSet { defaults.set(otherJobAlerts, forKey: "otherJobAlerts") } }
    var focusNow: Bool { didSet { defaults.set(focusNow, forKey: "focusNow") } }
    var focusSchedule: Bool { didSet { defaults.set(focusSchedule, forKey: "focusSchedule") } }
    var focusStartMinute: Int { didSet { defaults.set(focusStartMinute, forKey: "focusStartMinute") } }
    var focusEndMinute: Int { didSet { defaults.set(focusEndMinute, forKey: "focusEndMinute") } }
    var petVisible: Bool { didSet { defaults.set(petVisible, forKey: "petVisible") } }
    var roaming: Bool { didSet { defaults.set(roaming, forKey: "roaming") } }
    var petScale: Double { didSet { defaults.set(petScale, forKey: "petScale") } }
    var showMenuCredits: Bool { didSet { defaults.set(showMenuCredits, forKey: "showMenuCredits") } }
    var menuBarAlerts: Bool { didSet { defaults.set(menuBarAlerts, forKey: "menuBarAlerts") } }
    var completionAlerts: Bool { didSet { defaults.set(completionAlerts, forKey: "completionAlerts") } }
    var failureAlerts: Bool { didSet { defaults.set(failureAlerts, forKey: "failureAlerts") } }
    var lowCreditAlerts: Bool { didSet { defaults.set(lowCreditAlerts, forKey: "lowCreditAlerts") } }
    var sound: Bool { didSet { defaults.set(sound, forKey: "sound") } }
    // macOS 알림 소리와 별개로 지크의 붙잡힘·타자 효과음을 제어한다.
    var petSounds: Bool { didSet { defaults.set(petSounds, forKey: "petSounds") } }
    var petSoundVolume: Double { didSet { defaults.set(petSoundVolume, forKey: "petSoundVolume") } }
    var lowCreditThreshold: Double { didSet { defaults.set(lowCreditThreshold, forKey: "lowCreditThreshold") } }
    /// 기본 설정을 등록하고 예전 70% 크기를 새 100% 기준으로 한 번 변환한다.
    init(defaults: UserDefaults = .standard, domainName: String = Bundle.main.bundleIdentifier ?? "kr.co.zcre.bunny.prototype") {
        self.defaults = defaults
        let persisted = defaults.persistentDomain(forName: domainName) ?? [:]
        if (persisted["petScaleVersion"] as? Int ?? 0) < 2 {
            // 사용자가 선택한 이전 크기를 새 기준으로 변환한다. 이전 70%는 새 100%다.
            if let oldScale = persisted["petScale"] as? Double {
                defaults.set(min(1.5, max(0.7, oldScale / 0.7)), forKey: "petScale")
            }
            defaults.set(2, forKey: "petScaleVersion")
        }
        defaults.register(defaults: ["petVisible": true, "roaming": true, "petScale": 1.0, "showMenuCredits": true, "menuBarAlerts": true, "completionAlerts": true, "failureAlerts": true, "lowCreditAlerts": true, "sound": false, "lowCreditThreshold": 50.0])
        defaults.register(defaults: ["petSounds": true, "petSoundVolume": 0.35])
        defaults.register(defaults: ["imageJobAlerts": true, "videoJobAlerts": true, "upscaleJobAlerts": true, "audioJobAlerts": true, "otherJobAlerts": true, "focusNow": false, "focusSchedule": false, "focusStartMinute": 1320, "focusEndMinute": 480])
        imageJobAlerts = defaults.bool(forKey: "imageJobAlerts")
        videoJobAlerts = defaults.bool(forKey: "videoJobAlerts")
        upscaleJobAlerts = defaults.bool(forKey: "upscaleJobAlerts")
        audioJobAlerts = defaults.bool(forKey: "audioJobAlerts")
        otherJobAlerts = defaults.bool(forKey: "otherJobAlerts")
        focusNow = defaults.bool(forKey: "focusNow")
        focusSchedule = defaults.bool(forKey: "focusSchedule")
        focusStartMinute = min(1439, max(0, defaults.integer(forKey: "focusStartMinute")))
        focusEndMinute = min(1439, max(0, defaults.integer(forKey: "focusEndMinute")))
        petVisible = defaults.bool(forKey: "petVisible"); roaming = defaults.bool(forKey: "roaming")
        petScale = min(1.5, max(0.7, defaults.double(forKey: "petScale")))
        showMenuCredits = defaults.bool(forKey: "showMenuCredits")
        menuBarAlerts = defaults.bool(forKey: "menuBarAlerts")
        completionAlerts = defaults.bool(forKey: "completionAlerts"); failureAlerts = defaults.bool(forKey: "failureAlerts")
        lowCreditAlerts = defaults.bool(forKey: "lowCreditAlerts"); sound = defaults.bool(forKey: "sound")
        petSounds = defaults.bool(forKey: "petSounds")
        let savedVolume = defaults.double(forKey: "petSoundVolume")
        petSoundVolume = savedVolume.isFinite ? min(1, max(0, savedVolume)) : 0.35
        lowCreditThreshold = max(0, defaults.double(forKey: "lowCreditThreshold"))
    }
    /// 매일 현지 시각으로 평가하며 종료 시각은 포함하지 않는다. 같은 시각은 하루 종일이다.
    func isFocusActive(at date: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        if focusNow { return true }
        guard focusSchedule else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if focusStartMinute == focusEndMinute { return true }
        if focusStartMinute < focusEndMinute { return minute >= focusStartMinute && minute < focusEndMinute }
        return minute >= focusStartMinute || minute < focusEndMinute
    }

    /// 업스케일을 매체보다 먼저 분류해 영상 알림과 독립적으로 선택한다.
    func allowsJobAlert(_ job: GenerationJob) -> Bool {
        if job.model.lowercased().contains("upscale") { return upscaleJobAlerts }
        switch job.mediaType.lowercased() {
        case "image": return imageJobAlerts
        case "video": return videoJobAlerts
        case "audio": return audioJobAlerts
        default: return otherJobAlerts
        }
    }

}
