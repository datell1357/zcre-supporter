// 기능 분류: macOS 알림 권한 · 로컬 알림 전달
import AppKit
import UserNotifications
import ZCRECore

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    var openAlerts: (() -> Void)?
    /// macOS 알림 센터의 표시·클릭 콜백을 등록한다.
    override init() { super.init(); center.delegate = self }
    /// 사용자가 시스템에서 선택한 현재 알림 권한을 읽는다.
    func authorization() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    /// macOS 알림 승인 창을 요청하고 허용 여부를 반환한다.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }
    /// 아직 결정하지 않은 권한만 첫 실행에서 요청해 기존 선택을 반복해서 묻지 않는다.
    static func shouldRequestOnLaunch(_ status: UNAuthorizationStatus) -> Bool { status == .notDetermined }
    /// 번들 식별자를 URL 구성 요소로 인코딩해 이 앱의 알림 설정 링크를 만든다.
    static func settingsURL(bundleIdentifier: String) -> URL {
        var components = URLComponents(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        components.queryItems = [URLQueryItem(name: "id", value: bundleIdentifier)]
        return components.url!
    }
    /// 이 앱의 알림 시스템 설정 화면을 연다.
    func openSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? "kr.co.zcre.bunny.prototype"
        NSWorkspace.shared.open(Self.settingsURL(bundleIdentifier: bundleID))
    }
    /// 권한과 취소 여부를 확인한 뒤 로컬 macOS 알림을 등록한다. ZCRE 서버로 전송하지 않는다.
    func send(title: String, body: String, sound: Bool, identifier: String = UUID().uuidString) async -> Bool {
        let status = await authorization()
        guard !Task.isCancelled, status == .authorized || status == .provisional else { return false }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.categoryIdentifier = "ZCRE_JOB"
        if sound { content.sound = .default }
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            if Task.isCancelled {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                center.removeDeliveredNotifications(withIdentifiers: [identifier])
                return false
            }
            return true
        } catch { return false }
    }
    /// 앱이 예약했거나 이미 표시한 macOS 알림을 정리한다.
    func clear() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
    /// 앱 사용 중에도 허용된 로컬 알림을 배너와 지정된 소리로 표시한다.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
    /// 사용자가 알림을 누르면 메인 액터에서 앱의 현황 열기 콜백을 실행한다.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        await MainActor.run { self.openAlerts?() }
    }
}
