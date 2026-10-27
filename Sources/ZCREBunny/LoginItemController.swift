// 기능 분류: macOS 로그인 항목 등록 상태
import Observation
import ServiceManagement

@MainActor @Observable
final class LoginItemController {
    private(set) var status = SMAppService.mainApp.status
    private(set) var message: String?
    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var requiresApproval: Bool { status == .requiresApproval }
    var label: String {
        switch status {
        case .enabled: "Mac 로그인 시 자동으로 시작해요."
        case .requiresApproval: "시스템 설정에서 실행을 허용해 주세요."
        case .notFound: "앱을 응용 프로그램 폴더로 옮긴 뒤 다시 설정해 주세요."
        default: "자동 실행이 꺼져 있어요."
        }
    }
    /// 시스템의 실제 로그인 항목 상태를 다시 읽는다.
    func refresh() { status = SMAppService.mainApp.status }
    /// 사용자 선택에 따라 로그인 자동 실행을 등록·해제하고 오류를 설정 화면에 전달한다.
    func setEnabled(_ enabled: Bool) {
        message = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            message = "설정을 바꾸지 못했어요. 응용 프로그램 폴더에 설치한 뒤 로그인 항목을 확인해 주세요."
        }
        refresh()
    }
    /// 사용자 승인이 필요한 로그인 항목 시스템 설정을 연다.
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
