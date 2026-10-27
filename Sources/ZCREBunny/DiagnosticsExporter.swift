// 기능 분류: 사용자가 요청한 진단 파일 내보내기
import AppKit
import UniformTypeIdentifiers

enum AppInfo {
    static var name: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "ZCRE 서포터" }
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "개발 버전" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
}

@MainActor
enum DiagnosticsExporter {
    /// 앱·OS·연결 상태의 허용 목록만 저장한다. 계정·잔액·작업 내용·인증 토큰은 포함하지 않는다.
    static func export(store: CompanionStore, loginItem: LoginItemController) {
        // 명시한 진단 항목만 내보낸다. 계정·잔액·토큰·프롬프트·URL·작업 ID는 제외한다.
        var report: [String: Any] = [
            "formatVersion": 1,
            "appVersion": AppInfo.version,
            "appBuild": AppInfo.build,
            "generatedAt": ISO8601DateFormatter().string(from: .now),
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "connection": store.connection.label,
            "isRefreshing": store.isRefreshing,
            "isStale": store.isStale,
            "isDemo": store.isDemo,
            "activeJobCount": store.activeJobs.count,
            "unreadAlertCount": store.unreadAlertCount,
            "notificationAuthorization": store.notificationStatus.rawValue,
            "petVisible": store.preferences.petVisible,
            "petScale": store.preferences.petScale,
            "menuBarAlerts": store.preferences.menuBarAlerts,
            "launchAtLogin": loginItem.status.rawValue,
            "displayCount": NSScreen.screens.count
        ]
        #if arch(arm64)
        report["architecture"] = "arm64"
        #elseif arch(x86_64)
        report["architecture"] = "x86_64"
        #endif
        if let date = store.snapshot?.fetchedAt { report["snapshotAgeSeconds"] = Int(max(0, Date.now.timeIntervalSince(date))) }
        let panel = NSSavePanel()
        panel.title = "진단 정보 저장"; panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ZCRE-Supporter-diagnostics.json"
        panel.message = "앱·운영체제 버전과 연결 상태만 저장해요. 계정, 크레딧 잔액과 작업 내용은 포함하지 않아요."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.messageText = "진단 정보를 저장하지 못했어요"
            alert.informativeText = "저장 위치의 쓰기 권한과 여유 공간을 확인해 주세요."
            alert.runModal()
        }
    }
}
