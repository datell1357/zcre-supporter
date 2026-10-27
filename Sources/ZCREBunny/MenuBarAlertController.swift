// 기능 분류: 지크 숨김 시 메뉴 막대 아래 알림 배너
import AppKit
import SwiftUI

private final class MenuAlertPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class MenuBarAlertController {
    private let panel = MenuAlertPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var dismissTask: Task<Void, Never>?

    /// 키보드 포커스를 빼앗지 않는 투명 배너 창을 준비한다.
    init() {
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)
    }

    /// 메뉴 막대 버튼 근처의 화면 안에 배너를 배치하고 8초 후 닫는다.
    func show(_ alert: CompanionAlert, unreadCount: Int, near button: NSStatusBarButton, open: @escaping () -> Void) {
        guard let window = button.window, let screen = window.screen else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        let size = CGSize(width: min(340, visible.width - 24), height: 144)
        let x = min(visible.maxX - size.width - 12, max(visible.minX + 12, anchor.midX - size.width / 2))
        let y = max(visible.minY + 12, min(visible.maxY, anchor.minY) - size.height - 10)
        panel.contentView = NSHostingView(rootView: MenuBarAlertView(alert: alert, unreadCount: unreadCount, open: { [weak self] in self?.hide(); open() }, close: { [weak self] in self?.hide() }))
        panel.setFrame(NSRect(origin: CGPoint(x: x, y: y), size: size), display: true)
        // 비활성 패널로 알림을 표시해 다른 앱의 키보드 포커스를 가져오지 않는다.
        panel.orderFrontRegardless()
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            self?.hide()
        }
    }

    /// 닫기 예약을 취소하고 현재 배너를 숨긴다.
    func hide() { dismissTask?.cancel(); dismissTask = nil; panel.orderOut(nil) }
}

private struct MenuBarAlertView: View {
    let alert: CompanionAlert
    let unreadCount: Int
    let open: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: alert.kind.symbol).foregroundStyle(alert.kind == .completed ? BunnyTheme.success : .orange)
                Text("\(AppInfo.name) · 지크").font(.system(size: 11, weight: .semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 10)).frame(width: 22, height: 22) }
                    .buttonStyle(.plain).accessibilityLabel("배너 닫기")
            }
            Text(alert.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(alert.body).font(.system(size: 11)).foregroundStyle(BunnyTheme.muted).lineLimit(2)
            Spacer(minLength: 0)
            Button("알림 보기\(unreadCount > 1 ? " · \(unreadCount)개" : "")", action: open)
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(BunnyTheme.accent)
        }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(BunnyTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BunnyTheme.border))
            .foregroundStyle(BunnyTheme.foreground).preferredColorScheme(.dark)
    }
}
