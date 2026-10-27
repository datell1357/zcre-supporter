// 검증 분류: 로컬 데이터와 번들 리소스 기반 회귀 테스트. 실제 생성·결제 요청은 보내지 않는다.
import Foundation
import Testing
import UserNotifications
@testable import ZCREBunny

// 최초 미결정 권한만 요청하고 기존 허용·거부 선택을 존중하는지 검증한다.
@Test @MainActor func firstLaunchRequestsPermissionWithoutRepromptingPastDecisions() {
    #expect(NotificationService.shouldRequestOnLaunch(.notDetermined))
    #expect(!NotificationService.shouldRequestOnLaunch(.denied))
    #expect(!NotificationService.shouldRequestOnLaunch(.authorized))
    #expect(!NotificationService.shouldRequestOnLaunch(.provisional))
}

// 시스템 알림 설정 링크가 이 앱을 대상으로 하는지 검증한다.
@Test @MainActor func notificationSettingsLinkTargetsThisApp() {
    let url = NotificationService.settingsURL(bundleIdentifier: "kr.co.zcre.bunny.prototype")
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    #expect(components.scheme == "x-apple.systempreferences")
    #expect(components.path == "com.apple.Notifications-Settings.extension")
    #expect(components.queryItems == [URLQueryItem(name: "id", value: "kr.co.zcre.bunny.prototype")])
}
