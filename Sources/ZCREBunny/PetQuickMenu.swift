// 기능 분류: 지크 원형 메뉴 · 이미지/영상 도구의 공식 웹 바로가기
import AppKit
import SwiftUI
import ZCRECore

/// 정해진 공식 경로만 사용한다. 메뉴 열기·분류 선택에는 네트워크 요청이나 파일 업로드가 없다.
enum ZCREQuickTool: String, CaseIterable, Identifiable {
    case image, characterSheet, partialEdit, backgroundRemoval, imageUpscale, resize
    case video, videoUpscale, frameInterpolation, videoTranslate, videoReframe, depth
    case jiujitsu, audio, canvas, zcut
    var id: String { rawValue }
    var isImage: Bool { [.image, .characterSheet, .partialEdit, .backgroundRemoval, .imageUpscale, .resize].contains(self) }
    var isVideo: Bool { [.video, .videoUpscale, .frameInterpolation, .videoTranslate, .videoReframe].contains(self) }
    var title: String {
        switch self {
        case .image: "이미지 생성"
        case .characterSheet: "캐릭터 시트"
        case .partialEdit: "부분 수정"
        case .backgroundRemoval: "배경 제거"
        case .imageUpscale, .videoUpscale: "고화질 변환"
        case .resize: "사이즈 변환"
        case .video: "영상 생성"
        case .frameInterpolation: "프레임 보간"
        case .videoTranslate: "영상 번역"
        case .videoReframe: "세로 영상 변환"
        case .depth: "뎁스 맵"
        case .jiujitsu: "주짓수"
        case .audio: "오디오"
        case .canvas: "캔버스"
        case .zcut: "ZCUT"
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
        case .videoReframe: "rectangle.portrait"
        case .depth: "cube"
        case .jiujitsu: "figure.martial.arts"
        case .audio: "waveform"
        case .canvas: "square.stack.3d.up"
        case .zcut: "scissors"
        }
    }
    var url: URL {
        let address: String = switch self {
        case .image: "https://www.zcre.co.kr/studio/image"
        case .characterSheet: "https://www.zcre.co.kr/studio/character-sheet"
        case .partialEdit: "https://www.zcre.co.kr/studio/partial-edit"
        case .backgroundRemoval: "https://www.zcre.co.kr/studio/image?tool=background-removal"
        case .imageUpscale: "https://www.zcre.co.kr/studio/image?tool=upscale"
        case .resize: "https://www.zcre.co.kr/studio/image?tool=resize"
        case .video: "https://www.zcre.co.kr/studio/video"
        case .videoUpscale: "https://www.zcre.co.kr/studio/image?tool=upscale&media=video"
        case .frameInterpolation: "https://www.zcre.co.kr/studio/frame-interpolation"
        case .videoTranslate: "https://www.zcre.co.kr/studio/video-translate"
        case .videoReframe: "https://www.zcre.co.kr/studio/video-reframe"
        case .depth: "https://www.zcre.co.kr/studio/video-depth"
        case .jiujitsu: "https://www.zcre.co.kr/studio/jiujitsu"
        case .audio: "https://www.zcre.co.kr/studio/audio"
        case .canvas: "https://www.zcre.co.kr/studio/canvas"
        case .zcut: "https://zcut.ai/projects"
        }
        return URL(string: address)!
    }

    /// 작업 창 도구 메뉴의 분류. 지크 원형 메뉴의 이미지·영상·오디오·도구와 같다.
    static let groups: [(title: String, tools: [ZCREQuickTool])] = [
        ("이미지", allCases.filter(\.isImage)),
        ("영상", allCases.filter(\.isVideo)),
        ("오디오", [.audio]),
        ("도구", [.jiujitsu, .zcut, .canvas, .depth])
    ]

    /// 웹 안에서 이동한 주소가 어떤 도구 화면인지 찾는다. 경로와 쿼리가 모두 같은 도구를 우선한다.
    static func matching(_ url: URL) -> ZCREQuickTool? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let host = (parts.host ?? "").replacingOccurrences(of: "www.", with: "")
        let query = Set(parts.queryItems?.filter { ["tool", "media"].contains($0.name) }.map { "\($0.name)=\($0.value ?? "")" } ?? [])
        return allCases.first { tool in
            guard let target = URLComponents(url: tool.url, resolvingAgainstBaseURL: false) else { return false }
            let targetQuery = Set(target.queryItems?.map { "\($0.name)=\($0.value ?? "")" } ?? [])
            let targetHost = (target.host ?? "").replacingOccurrences(of: "www.", with: "")
            let samePath = tool == .zcut
                ? (parts.path.hasPrefix("/projects") || parts.path.hasPrefix("/editor/"))
                : target.path == parts.path
            return targetHost == host && samePath && targetQuery == query
        }
    }
}

struct PetQuickMenu: View {
    enum Category { case home, image, video, tools }
    var store: CompanionStore
    var close: () -> Void
    var openTool: (ZCREQuickTool) -> Void
    @State var category: Category = .home
    static let previewSize = CGSize(width: 980, height: 560)

    /// 미리보기에서도 운영 메뉴와 같은 배치를 사용한다. 중앙에는 배경과 버튼을 그리지 않는다.
    var body: some View {
        let items = QuickMenuItem.items(category)
        let screen = CGRect(origin: .zero, size: Self.previewSize)
        let anchor = CGRect(x: (screen.width - 90) / 2, y: (screen.height - 110) / 2, width: 90, height: 110)
        let layout = PetQuickMenuLayout(anchor: anchor, screen: screen, count: items.count, home: category == .home)
        ZStack(alignment: .topLeading) {
            Circle().stroke(BunnyTheme.border, lineWidth: 1)
                .frame(width: layout.radius * 2, height: layout.radius * 2)
                .position(x: anchor.midX, y: Self.previewSize.height - anchor.midY)
            PetStatusView(store: store, showSettings: {}, showsSettings: false)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BunnyTheme.border))
                .position(x: layout.summary.midX, y: Self.previewSize.height - layout.summary.midY)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if layout.buttons.indices.contains(index) {
                    QuickMenuButton(item: item, size: layout.buttons[index].width) {
                        switch item.action {
                        case .category(let next): category = next
                        case .tool(let tool): openTool(tool)
                        }
                    }.position(x: layout.buttons[index].midX, y: Self.previewSize.height - layout.buttons[index].midY)
                }
            }
        }.frame(width: Self.previewSize.width, height: Self.previewSize.height).preferredColorScheme(.dark)
    }
}

private struct QuickMenuItem: Identifiable {
    enum Action { case category(PetQuickMenu.Category), tool(ZCREQuickTool) }
    let id: String
    let title: String
    let symbol: String
    let action: Action
    static func items(_ category: PetQuickMenu.Category) -> [Self] {
        if category == .home {
            return [.init(id: "image", title: "이미지", symbol: "photo", action: .category(.image)),
                    .init(id: "video", title: "영상", symbol: "video", action: .category(.video)),
                    .init(id: "audio", title: "오디오", symbol: ZCREQuickTool.audio.symbol, action: .tool(.audio)),
                    .init(id: "tools", title: "도구", symbol: "wrench.and.screwdriver", action: .category(.tools))]
        }
        if category == .tools {
            return [.jiujitsu, .zcut, .canvas, .depth, .resize]
                .map { .init(id: $0.id, title: $0.title, symbol: $0.symbol, action: .tool($0)) }
                + [.init(id: "back", title: "뒤로", symbol: "arrow.left", action: .category(.home))]
        }
        return ZCREQuickTool.allCases.filter { category == .video ? $0.isVideo : $0.isImage }
            .map { .init(id: $0.id, title: $0.title, symbol: $0.symbol, action: .tool($0)) }
            + [.init(id: "back", title: "뒤로", symbol: "arrow.left", action: .category(.home))]
    }
}

private struct QuickMenuButton: View {
    let item: QuickMenuItem
    let size: CGFloat
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        let compact = size < 52
        let tiny = size < 46
        Button(action: action) {
            VStack(spacing: tiny ? 1 : compact ? 2 : 3) {
                Image(systemName: item.symbol).font(.system(size: tiny ? 12 : compact ? 14 : 16, weight: .medium))
                    .frame(height: tiny ? 12 : compact ? 14 : 16)
                Text(item.title.replacingOccurrences(of: " ", with: "\n"))
                    .font(.system(size: tiny ? 9 : compact ? 9.5 : 10, weight: .semibold))
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                    .lineSpacing(-1)
                    .frame(width: tiny ? 35 : compact ? 39 : 44)
            }.padding(.vertical, tiny ? 3 : compact ? 5 : 6)
                .frame(width: size, height: size)
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
        decoration = makePanel(
            Circle().stroke(BunnyTheme.border.opacity(0.8), lineWidth: 1),
            frame: CGRect(x: anchor.midX - layout.radius, y: anchor.midY - layout.radius, width: layout.radius * 2, height: layout.radius * 2),
            decorative: true
        )
        let summary = PetStatusView(store: store, showSettings: {}, showsSettings: false)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BunnyTheme.border))
        panels.append(makePanel(summary, frame: layout.summary))
        for (index, item) in items.enumerated() where layout.buttons.indices.contains(index) {
            panels.append(makePanel(QuickMenuButton(item: item, size: layout.buttons[index].width) { [weak self] in
                guard let self else { return }
                switch item.action {
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
