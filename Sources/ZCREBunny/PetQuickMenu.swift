// 기능 분류: 지크 원형 메뉴 · 이미지/영상 도구의 공식 웹 바로가기
import AppKit
import SwiftUI
import ZCRECore

/// 정해진 공식 경로만 사용한다. 메뉴 열기·분류 선택에는 네트워크 요청이나 파일 업로드가 없다.
enum ZCREQuickTool: String, CaseIterable, Identifiable {
    case image, characterSheet, partialEdit, backgroundRemoval, imageUpscale, resize
    case video, videoUpscale, frameInterpolation, videoTranslate
    case jiujitsu, audio, canvas
    var id: String { rawValue }
    var isImage: Bool { [.image, .characterSheet, .partialEdit, .backgroundRemoval, .imageUpscale, .resize].contains(self) }
    var isVideo: Bool { [.video, .videoUpscale, .frameInterpolation, .videoTranslate].contains(self) }
    var title: String {
        switch self {
        case .image: "이미지 생성"
        case .characterSheet: "캐릭터 시트"
        case .partialEdit: "부분 수정"
        case .backgroundRemoval: "배경 제거"
        case .imageUpscale, .videoUpscale: "고화질 변환"
        case .resize: "크기 변환"
        case .video: "영상 생성"
        case .frameInterpolation: "프레임 보간"
        case .videoTranslate: "영상 번역"
        case .jiujitsu: "주짓수"
        case .audio: "오디오"
        case .canvas: "캔버스"
        }
    }
    var symbol: String {
        switch self {
        case .image: "photo.badge.plus"
        case .characterSheet: "person.crop.rectangle.stack"
        case .partialEdit: "paintbrush.pointed"
        case .backgroundRemoval: "eraser"
        case .imageUpscale, .videoUpscale: "sparkles"
        case .resize: "arrow.up.left.and.arrow.down.right"
        case .video: "video.badge.plus"
        case .frameInterpolation: "film.stack"
        case .videoTranslate: "captions.bubble"
        case .jiujitsu: "figure.martial.arts"
        case .audio: "waveform"
        case .canvas: "square.stack.3d.up"
        }
    }
    var url: URL {
        let path: String = switch self {
        case .image: "/studio/image"
        case .characterSheet: "/studio/character-sheet"
        case .partialEdit: "/studio/partial-edit"
        case .backgroundRemoval: "/studio/image?tool=background-removal"
        case .imageUpscale: "/studio/image?tool=upscale"
        case .resize: "/studio/image?tool=resize"
        case .video: "/studio/video"
        case .videoUpscale: "/studio/image?tool=upscale&media=video"
        case .frameInterpolation: "/studio/frame-interpolation"
        case .videoTranslate: "/studio/video-translate"
        case .jiujitsu: "/studio/jiujitsu"
        case .audio: "/studio/audio"
        case .canvas: "/studio/canvas"
        }
        return URL(string: "https://www.zcre.co.kr" + path)!
    }
}

struct PetQuickMenu: View {
    enum Category { case home, image, video }
    var store: CompanionStore
    var close: () -> Void
    var openTool: (ZCREQuickTool) -> Void
    @State var category: Category = .home
    static let size: CGFloat = 560

    /// 미리보기에서도 운영 메뉴와 같은 배치를 사용한다. 중앙에는 배경과 버튼을 그리지 않는다.
    var body: some View {
        let items = QuickMenuItem.items(category)
        let layout = PetQuickMenuLayout(anchor: CGRect(x: 235, y: 225, width: 90, height: 110),
                                        screen: CGRect(x: 0, y: 0, width: Self.size, height: Self.size), count: items.count, home: category == .home)
        ZStack(alignment: .topLeading) {
            MenuArc().stroke(BunnyTheme.border, lineWidth: 1)
                .frame(width: layout.radius * 2, height: layout.radius * 2)
                .position(x: 280, y: 280)
            PetStatusView(store: store, showSettings: {}, showsSettings: false)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BunnyTheme.border))
                .position(x: layout.summary.midX, y: Self.size - layout.summary.midY)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if layout.buttons.indices.contains(index) {
                    QuickMenuButton(item: item, size: layout.buttons[index].width) {
                        switch item.action {
                        case .category(let next): category = next
                        case .close: close()
                        case .tool(let tool): openTool(tool)
                        }
                    }.position(x: layout.buttons[index].midX, y: Self.size - layout.buttons[index].midY)
                }
            }
        }.frame(width: Self.size, height: Self.size).preferredColorScheme(.dark)
    }
}

private struct QuickMenuItem: Identifiable {
    enum Action { case category(PetQuickMenu.Category), tool(ZCREQuickTool), close }
    let id: String
    let title: String
    let symbol: String
    let action: Action
    static func items(_ category: PetQuickMenu.Category) -> [Self] {
        if category == .home {
            return [.init(id: "image", title: "이미지", symbol: "photo", action: .category(.image)),
                    .init(id: "video", title: "영상", symbol: "video", action: .category(.video)),
                    .init(id: "jiujitsu", title: "주짓수", symbol: ZCREQuickTool.jiujitsu.symbol, action: .tool(.jiujitsu)),
                    .init(id: "audio", title: "오디오", symbol: ZCREQuickTool.audio.symbol, action: .tool(.audio)),
                    .init(id: "close", title: "닫기", symbol: "xmark", action: .close),
                    .init(id: "canvas", title: "캔버스", symbol: ZCREQuickTool.canvas.symbol, action: .tool(.canvas))]
        }
        return ZCREQuickTool.allCases.filter { category == .video ? $0.isVideo : $0.isImage }
            .map { .init(id: $0.id, title: $0.title, symbol: $0.symbol, action: .tool($0)) }
            + [.init(id: "back", title: "뒤로", symbol: "arrow.left", action: .category(.home)),
               .init(id: "close", title: "닫기", symbol: "xmark", action: .close)]
    }
}

private struct MenuArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                    startAngle: .degrees(-45), endAngle: .degrees(225), clockwise: false)
        return path
    }
}

private struct QuickMenuButton: View {
    let item: QuickMenuItem
    let size: CGFloat
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: item.symbol).font(.system(size: 16, weight: .medium))
                    .frame(height: 16)
                // 긴 도구명은 단어 경계에서 두 줄로 나눠 원 안의 안전한 폭에 넣는다.
                Text(item.title.replacingOccurrences(of: " ", with: "\n"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.9)
                    .frame(width: 40, height: 26)
            }.frame(width: size, height: size)
                .foregroundStyle(BunnyTheme.foreground)
                .background(hovered ? BunnyTheme.elevated : BunnyTheme.surface, in: Circle())
                .overlay(Circle().strokeBorder(hovered ? BunnyTheme.accent : BunnyTheme.border))
                .contentShape(Circle())
        }.buttonStyle(.plain).onHover { hovered = $0 }.accessibilityLabel(item.title).help(item.title)
    }
}

@MainActor final class PetQuickMenuController {
    private final class MenuPanel: NSPanel { override var canBecomeKey: Bool { true } }
    // 중앙에 이벤트를 받는 창을 두지 않는다. 지크 클릭·드래그가 실제 펫 창으로 그대로 전달된다.
    private var panels: [NSPanel] = []
    private var decoration: NSPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var store: CompanionStore?
    private weak var petWindow: NSWindow?
    private var anchor = CGRect.zero
    private var labelWidth: CGFloat = 110
    private var screen = CGRect.zero
    private var category: PetQuickMenu.Category = .home
    private var openTool: ((ZCREQuickTool) -> Void)?
    var onClose: (() -> Void)?
    var isShown: Bool { !panels.isEmpty }

    /// 현황과 각 버튼을 작은 투명 창으로 분리하여 가운데의 지크와 작업 문구를 가리지 않는다.
    func show(store: CompanionStore, anchor: CGRect, screen: CGRect, petWindow: NSWindow, labelWidth: CGFloat = 110, openTool: @escaping (ZCREQuickTool) -> Void) {
        close()
        self.store = store; self.anchor = anchor; self.screen = screen; self.labelWidth = labelWidth
        self.petWindow = petWindow; self.openTool = openTool; category = .home
        rebuild()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 { self.close(); return nil }
            if event.type != .keyDown && !self.panels.contains(where: { $0 === event.window }) && event.window !== self.petWindow { self.close() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func makePanel<V: View>(_ view: V, frame: CGRect, decorative: Bool = false) -> NSPanel {
        let panel = MenuPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.isOpaque = false
        panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .popUpMenu; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = decorative
        panel.contentView = NSHostingView(rootView: view)
        panel.orderFrontRegardless()
        return panel
    }

    private func rebuild() {
        guard let store else { return }
        for panel in panels { panel.contentView = nil; panel.orderOut(nil) }
        panels.removeAll(); decoration?.orderOut(nil); decoration = nil
        let items = QuickMenuItem.items(category)
        let layout = PetQuickMenuLayout(anchor: anchor, screen: screen, count: items.count, home: category == .home, labelWidth: labelWidth)
        let radius = layout.radius
        decoration = makePanel(MenuArc().stroke(BunnyTheme.border.opacity(0.8), lineWidth: 1),
                               frame: CGRect(x: anchor.midX - radius, y: anchor.midY - radius, width: radius * 2, height: radius * 2), decorative: true)
        let summary = PetStatusView(store: store, showSettings: {}, showsSettings: false)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BunnyTheme.border))
        panels.append(makePanel(summary, frame: layout.summary))
        for (index, item) in items.enumerated() where layout.buttons.indices.contains(index) {
            panels.append(makePanel(QuickMenuButton(item: item, size: layout.buttons[index].width) { [weak self] in
                guard let self else { return }
                switch item.action {
                case .close: self.close()
                case .category(let next): self.category = next; self.rebuild()
                case .tool(let tool): let open = self.openTool; self.close(); open?(tool)
                }
            }, frame: layout.buttons[index]))
        }
        panels.first?.makeKey()
    }

    /// 메뉴 종료 시 전역 이벤트 감시와 모든 작은 창을 함께 해제한다.
    func close() {
        let wasShown = isShown
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; globalMonitor = nil
        for panel in panels { panel.contentView = nil; panel.orderOut(nil) }
        panels.removeAll(); decoration?.orderOut(nil); decoration = nil
        store = nil; openTool = nil; petWindow = nil
        if wasShown { onClose?() }
    }
}
