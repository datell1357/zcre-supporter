// 기능 분류: 로컬 데모 미리보기 이미지 내보내기
import AppKit
import SwiftUI

/// 개발용 미리보기 렌더러로 실제 바탕화면을 촬영하거나 계정 데이터를 읽지 않는다.
@MainActor
enum PreviewExporter {
    /// 실제 앱 뷰와 명시적인 가상 데이터로 2560×1600 스토어 설명 이미지를 만든다.
    static func exportStore(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "kr.co.zcre.bunny.preview")!
        let store = CompanionStore(preferences: Preferences(defaults: defaults, domainName: "kr.co.zcre.bunny.preview"))
        store.enterDemo()
        func save<V: View>(_ view: V, title: String, subtitle: String, name: String) {
            let scene = HStack(spacing: 36) {
                VStack(alignment: .leading, spacing: 24) {
                    Text("ZCRE 서포터").font(.system(size: 22, weight: .heavy)).foregroundStyle(BunnyTheme.accent)
                    Text(title).font(.system(size: 34, weight: .bold))
                    Text(subtitle).font(.system(size: 17)).foregroundStyle(BunnyTheme.muted)
                    RabbitView(animate: false).frame(width: 190, height: 230)
                    Text("미리보기 모드 · 가상 데이터와 번들 샘플").font(.system(size: 11)).foregroundStyle(BunnyTheme.muted)
                }.frame(width: 300, alignment: .leading)
                view.clipShape(RoundedRectangle(cornerRadius: 18))
            }.frame(width: 1280, height: 800).background(BunnyTheme.background)
                .foregroundStyle(BunnyTheme.foreground).preferredColorScheme(.dark)
            // AppKit 기반 Picker·ScrollView도 실제로 그리도록 호스팅 창에서 캡처한다.
            let size = NSSize(width: 2560, height: 1600)
            let host = NSHostingView(rootView: scene.scaleEffect(2, anchor: .topLeading)
                .frame(width: size.width, height: size.height, alignment: .topLeading))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host; host.setFrameSize(size); host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2560, pixelsHigh: 1600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
            bitmap.size = size; host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: directory.appendingPathComponent(name + ".png"))
        }
        save(MenuBarView(store: store, serviceStatus: ServiceStatusStore(), showDashboard: {}, showSettings: {}, close: {}, size: CGSize(width: 840, height: 600)),
             title: "필요한 현황을\n한눈에", subtitle: "크레딧 · 작업 · 최근 알림 · 서비스 상태", name: "01-status")
        save(SettingsView(store: store, resetPosition: {}), title: "내 작업 리듬에\n맞추는 지크", subtitle: "표시 · 산책 · 소리 · 작업별 알림", name: "02-settings")
        save(DemoResultView(store: store), title: "결과를 재생하고\n원하는 곳에 저장", subtitle: "이미지 · 영상 · 오디오 미리보기", name: "03-results")
        print("store-ui=exported")
    }
    /// 네트워크 조회 없이 세 패널의 배치와 가독성을 검토한다.
    static func exportMenu(to url: URL) {
        let defaults = UserDefaults(suiteName: "kr.co.zcre.bunny.preview")!
        let store = CompanionStore(preferences: Preferences(defaults: defaults, domainName: "kr.co.zcre.bunny.preview"))
        store.enterDemo()
        let size = MenuBarView.preferredSize
        let host = NSHostingView(rootView: MenuBarView(store: store, serviceStatus: ServiceStatusStore(), showDashboard: {}, showSettings: {}, close: {}, size: size))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host; host.setFrameSize(size); host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: url) }
    }

    /// 홍보용 UI를 실제 SwiftUI 뷰에서 2배 해상도로 출력한다. 계정 데이터는 로컬 데모만 사용한다.
    static func exportPromoUI(to directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "kr.co.zcre.bunny.preview")!
        let store = CompanionStore(preferences: Preferences(defaults: defaults, domainName: "kr.co.zcre.bunny.preview"))
        store.enterDemo()
        func save<V: View>(_ view: V, _ name: String, size: CGSize = CGSize(width: 384, height: 384)) {
            if name != "dashboard" {
                let renderer = ImageRenderer(content: view); renderer.scale = 2
                if let image = renderer.cgImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                    try? png.write(to: directory.appendingPathComponent(name + ".png"))
                }
                return
            }
            let size = CGSize(width: size.width * 2, height: size.height * 2)
            let host = NSHostingView(rootView: view.scaleEffect(2, anchor: .topLeading).frame(width: size.width, height: size.height, alignment: .topLeading))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear
            window.contentView = host; host.setFrameSize(size); host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
            bitmap.size = size
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: directory.appendingPathComponent(name + ".png"))
            }
        }
        for (name, category) in [("home", PetQuickMenu.Category.home), ("image", .image), ("video", .video)] {
            save(PetQuickMenu(store: store, close: {}, openTool: { _ in }, category: category), "menu-" + name, size: CGSize(width: PetQuickMenu.size, height: PetQuickMenu.size))
        }
        save(PetStatusView(store: store, showSettings: {}), "compact", size: PetStatusView.preferredSize)
        let status = ServiceStatusStore()
        if let task = status.refresh(manual: false) { await task.value }
        // 서비스 패널 단독 검수: 공개 실데이터만 포함하며 데모 계정 수치는 제외한다.
        let serviceSize = CGSize(width: MenuBarView.preferredSize.width * 0.34 - 2, height: 500)
        save(ServiceStatusView(status: status).frame(width: serviceSize.width, height: serviceSize.height)
            .background(BunnyTheme.background).foregroundStyle(BunnyTheme.foreground).preferredColorScheme(.dark),
            "service-status", size: serviceSize)
        save(MenuBarView(store: store, serviceStatus: status, showDashboard: {}, showSettings: {}, close: {}, size: MenuBarView.preferredSize), "dashboard", size: MenuBarView.preferredSize)
        status.stop()
        print("promo-ui=exported")
    }

    /// 실제 계정에 연결하지 않는 데모 화면을 PNG로 저장한다.
    static func export(to url: URL) {
        let defaults = UserDefaults(suiteName: "kr.co.zcre.bunny.preview")!
        let store = CompanionStore(preferences: Preferences(defaults: defaults, domainName: "kr.co.zcre.bunny.preview"))
        store.enterDemo()
        let preview = HStack(alignment: .center, spacing: 42) {
            VStack(alignment: .leading, spacing: 16) {
                Text("ZCRE\n서포터").font(.system(size: 53, weight: .bold, design: .rounded)).tracking(-2).foregroundStyle(.white)
                Text("작업 곁에, 지크.").font(.system(size: 17, weight: .medium)).foregroundStyle(BunnyTheme.accent)
                Text("바탕화면 펫 · 크레딧 · 완료 알림").font(.system(size: 12)).foregroundStyle(BunnyTheme.muted)
                RabbitView(animate: false).frame(width: 194, height: 236).padding(.top, 20)
                PetStatusView(store: store, showSettings: {})
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BunnyTheme.border))
                Text("\(AppInfo.version)  /  macOS 14+\n가상 데이터를 사용한 앱 UI 렌더링").font(.system(size: 10)).foregroundStyle(BunnyTheme.muted).lineSpacing(5)
            }.frame(width: 256, alignment: .leading)
            DashboardView(store: store, showSettings: {}, close: {}).clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.09)))
            SettingsView(store: store, resetPosition: {}).clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BunnyTheme.border))
        }.padding(48).background(BunnyTheme.background)
        let host = NSHostingView(rootView: preview)
        let size = NSSize(width: 1236, height: 796)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.setFrameSize(size)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("preview=FAIL"); return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        do {
            guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
            try png.write(to: url)
            print("preview=PASS")
        } catch { print("preview=FAIL") }
    }
}
