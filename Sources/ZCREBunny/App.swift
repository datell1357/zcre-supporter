// 기능 분류: 앱 생명주기 · 메뉴 막대 · 창 연결
import AppKit
import SwiftUI
import Observation
import ZCRECore

@main
struct ZCREBunnyApp {
    // MARK: - 실행 진입
    /// 미리보기 내보내기 인자를 처리하거나 메뉴 막대 앱의 메인 이벤트 루프를 시작한다.
    @MainActor static func main() {
        let app = NSApplication.shared
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            PreviewExporter.export(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-menu-preview"), CommandLine.arguments.count > index + 1 {
            PreviewExporter.exportMenu(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-promo-ui"), CommandLine.arguments.count > index + 1 {
            let destination = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task { await PreviewExporter.exportPromoUI(to: destination); app.terminate(nil) }
            app.run()
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(CommandLine.arguments.contains("--inspect-ui") ? .regular : .accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private let store = CompanionStore(preferences: Preferences())
    private var statusItem: NSStatusItem!
    private var activityIcon: MenuBarActivityIcon?
    private let menuAlerts = MenuBarAlertController()
    private let loginItem = LoginItemController()
    private let serviceStatus = ServiceStatusStore()
    private var bannerTask: Task<Void, Never>?
    private var pet: PetController!
    private let menuPopover = NSPopover()
    private let petPopover = NSPopover()
    private let quickMenu = PetQuickMenuController()
    private var settingsWindow: NSWindow?
    private var dashboardWindow: NSWindow?
    private var resultWindow: NSWindow?
    private var motionTestWindow: NSWindow?

    // MARK: - 앱 시작과 창 구성
    /// 창·메뉴·관찰 콜백을 한 번 연결하고 로그인 상태 감시와 첫 실행 알림 권한 흐름을 시작한다.
    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self; statusItem.button?.action = #selector(toggleFromMenu)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        if let button = statusItem.button { activityIcon = MenuBarActivityIcon(button: button) }
        statusItem.button?.imagePosition = .imageLeading
        for popover in [menuPopover, petPopover] {
            popover.behavior = .transient; popover.animates = false; popover.delegate = self
            popover.appearance = NSAppearance(named: .darkAqua)
        }
        pet = PetController(store: store)
        pet.onClick = { [weak self] in self?.toggleFromPet() }
        pet.onBeginDrag = { [weak self] in self?.quickMenu.close() }
        quickMenu.onClose = { [weak self] in
            guard let self else { return }
            self.pet.paused = self.menuPopover.isShown || self.petPopover.isShown
        }
        pet.showSettings = { [weak self] in self?.showSettings() }
        pet.showMotionTests = { [weak self] in self?.showMotionTests() }
        pet.onTestChange = { [weak self] in self?.updateStatus() }
        store.onChange = { [weak self] in
            guard let self else { return }
            self.updateStatus(); self.pet.updatePreferences()
            self.serviceStatus.setNetworkAvailable(!self.store.isOffline)
        }
        store.onAlert = { [weak self] alert in self?.receivedAlert(alert) }
        store.onAlertsReset = { [weak self] in self?.dismissMenuAlert() }
        store.openAlerts = { [weak self] in self?.showMenuAlerts() }
        store.showResult = { [weak self] job in self?.showResult(job) }
        observePreferences()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(accessibilityChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let demo = CommandLine.arguments.contains("--demo")
        store.start(demo: demo, reviewNotifications: !CommandLine.arguments.contains("--smoke-test"))
        updateStatus()
        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + (demo ? 2 : 12)) { [weak self] in
                guard let self else { return }
                let dataReady = self.store.isDemo ? self.store.snapshot != nil : self.store.webSession.isLoaded
                let valid = self.pet.panel.isVisible && self.statusItem.button != nil && dataReady
                print("launch=\(valid ? "PASS" : "FAIL") petVisible=\(self.pet.panel.isVisible) statusItem=\(self.statusItem.button != nil) demo=\(self.store.isDemo) webLoaded=\(self.store.webSession.isLoaded) signInRequired=\(self.store.connection == .signedOut)")
                NSApp.terminate(nil)
            }
        } else {
            let explicitWindow = ["--show-dashboard", "--connect", "--inspect-ui", "--demo"].contains(where: CommandLine.arguments.contains)
            let firstLaunch = !UserDefaults.standard.bool(forKey: "hasCompletedFirstLaunch")
            UserDefaults.standard.set(true, forKey: "hasCompletedFirstLaunch")
            // 첫 실행 이후에는 로그인 자동 실행을 포함해 메뉴 막대에서 조용히 감시한다.
            if explicitWindow || firstLaunch {
                DispatchQueue.main.async { [weak self] in self?.showPrimaryWindow() }
            }
        }
    }
    /// 실행 인자에 따라 계정 연결 창 또는 상세 현황 창을 연다.
    private func showPrimaryWindow() {
        if CommandLine.arguments.contains("--show-dashboard") {
            showDashboard()
        } else if CommandLine.arguments.contains("--connect") {
            store.connect()
        } else {
            showDashboard()
        }
    }
    /// 기존 팝오버와 배너를 닫고 상세 현황 창을 재사용하며 표시된 알림을 읽음 처리한다.
    @objc private func showDashboard() {
        dismissMenuAlert()
        closeStatusPopovers()
        if dashboardWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 370, height: 620), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = AppInfo.name
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(BunnyTheme.background); window.titlebarAppearsTransparent = true
            window.contentView = NSHostingView(rootView: DashboardView(store: store, showSettings: { [weak self] in self?.showSettings() }, close: { [weak window] in window?.orderOut(nil) }))
            window.isReleasedWhenClosed = false
            window.center()
            dashboardWindow = window
        }
        dashboardWindow?.makeKeyAndOrderFront(nil)
        store.markAlertsRead()
        NSApp.activate(ignoringOtherApps: true)
    }
    // MARK: - 설정 관찰과 메뉴 막대
    /// 표시 설정 변경을 관찰한 뒤 지크·메뉴 막대에 반영하고 일회성 관찰을 다시 등록한다.
    private func observePreferences() {
        withObservationTracking {
            _ = store.preferences.petVisible; _ = store.preferences.petScale; _ = store.preferences.roaming; _ = store.preferences.showMenuCredits; _ = store.preferences.menuBarAlerts
            _ = store.preferences.focusNow; _ = store.preferences.focusSchedule
            _ = store.preferences.focusStartMinute; _ = store.preferences.focusEndMinute
            _ = store.debugModeEnabled
            _ = store.preferences.petSounds; _ = store.preferences.petSoundVolume
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.store.refreshFocusPolicy()
                self.pet.updatePreferences(); self.updateStatus(); self.observePreferences()
                if self.store.preferences.petVisible || !self.store.preferences.menuBarAlerts { self.dismissMenuAlert() }
                if !self.store.preferences.petVisible { self.petPopover.performClose(nil); self.quickMenu.close() }
                if !self.store.debugModeEnabled {
                    self.pet.stopTest()
                    self.motionTestWindow?.orderOut(nil)
                }
            }
        }
    }
    /// 작업 상태는 지크 아이콘으로, 잔액은 숫자로 표시한다. 알림 개수는 덧붙이지 않는다.
    private func updateStatus() {
        activityIcon?.update(activeJobs: store.activeJobs.count, previewWorking: pet.motion.testMotion == .working, sleeping: store.isSleeping, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let suffix = store.isStale ? " ·" : ""
        let creditTitle = store.preferences.showMenuCredits ? " \(store.creditText)\(suffix)" : ""
        statusItem.button?.title = creditTitle
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let activity = store.activeJobs.isEmpty ? "진행 중인 작업 없음" : "\(store.activeJobs.count)개 작업 진행 중"
        statusItem.button?.toolTip = "\(AppInfo.name)\(store.isDemo ? " · 미리보기" : "") · 사용 가능 \(store.creditText) Credit · \(activity) · \(store.connection.label)"
        statusItem.button?.setAccessibilityLabel("\(AppInfo.name), 사용 가능 \(store.creditText) 크레딧, \(activity), \(store.connection.label)")
    }
    /// 메뉴 막대 왼쪽 클릭은 현황판을 토글하고 오른쪽 클릭은 명령 메뉴를 연다.
    @objc private func toggleFromMenu() {
        // 앱 활성화로 기존 상세 창까지 함께 올라오지 않도록 먼저 숨긴다.
        dashboardWindow?.orderOut(nil)
        if NSApp.currentEvent?.type == .rightMouseUp { showStatusMenu(); return }
        if menuPopover.isShown { menuPopover.performClose(nil); return }
        showMenuAlerts()
    }
    /// 선택한 완료 작업의 결과창을 하나만 유지한다.
    private func showResult(_ job: GenerationJob) {
        guard let workspace = store.snapshot?.workspaceKey else { return }
        closeStatusPopovers()
        resultWindow?.contentView = nil
        resultWindow?.close()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 660), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "작업 결과 · \(job.workName)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: JobResultView(store: store, job: job, workspace: workspace))
        resultWindow = window
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 최근 알림과 서비스 상태를 표시하며 공개 상태는 이 창이 열린 동안만 갱신한다.
    private func showMenuAlerts() {
        dismissMenuAlert()
        store.refreshForPresentation()
        petPopover.performClose(nil)
        quickMenu.close()
        if menuPopover.isShown { store.markAlertsRead(limit: MenuBarView.recentAlertLimit); return }
        guard let button = statusItem.button else { return }
        dashboardWindow?.orderOut(nil)
        pet.paused = true
        let bounds = button.window?.screen?.visibleFrame ?? pet.visibleScreenFrame
        let size = PopoverPlacement(anchor: .zero, visibleFrame: bounds, preferredSize: MenuBarView.preferredSize).contentSize
        menuPopover.contentViewController = NSHostingController(rootView: MenuBarView(store: store, serviceStatus: serviceStatus, showDashboard: { [weak self] in self?.showDashboard() }, showSettings: { [weak self] in self?.showSettings() }, close: { [weak self] in self?.menuPopover.performClose(nil) }, size: size))
        menuPopover.contentSize = size
        NSApp.activate(ignoringOtherApps: true)
        menuPopover.show(relativeTo: button.bounds, of: button, preferredEdge: button.isFlipped ? .maxY : .minY)
        if menuPopover.isShown { store.markAlertsRead(limit: MenuBarView.recentAlertLimit); serviceStatus.start() } else { pet.paused = false }
    }
    /// 새 알림을 현황판에 반영하거나 지크 숨김 상태에서 배너로 표시하며 연속 이벤트를 합친다.
    private func receivedAlert(_ alert: CompanionAlert) {
        if menuPopover.isShown { store.markAlertsRead(limit: MenuBarView.recentAlertLimit); return }
        guard !store.preferences.isFocusActive(), !store.preferences.petVisible, store.preferences.menuBarAlerts, !store.isSleeping else { return }
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            // 한 조회에서 여러 작업이 끝나면 배너는 합치고 각 알림 이력은 모두 보관한다.
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let self, !self.store.preferences.isFocusActive(), !self.store.preferences.petVisible, self.store.preferences.menuBarAlerts,
                  !self.store.isSleeping, !self.menuPopover.isShown, !self.petPopover.isShown, !self.quickMenu.isShown,
                  let button = self.statusItem.button else { return }
            self.menuAlerts.show(alert, unreadCount: self.store.unreadAlertCount, near: button) { [weak self] in self?.showMenuAlerts() }
        }
    }
    /// 예약된 배너와 현재 배너를 함께 닫아 뒤늦게 다시 나타나는 것을 방지한다.
    private func dismissMenuAlert() { bannerTask?.cancel(); bannerTask = nil; menuAlerts.hide() }
    /// 지크 표시 여부만 바꾸며 계정 데이터 감시는 계속 유지한다.
    @objc private func togglePetVisibility() { store.preferences.petVisible.toggle() }
    /// 메뉴 항목의 설정 동작을 단일 설정 창으로 연결한다.
    @objc private func openSettingsFromMenu() { showSettings() }
    /// 지크 표시·설정·상세 현황 및 디버그 전용 모션 명령을 구성한다.
    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        dismissMenuAlert(); closeStatusPopovers()
        let menu = NSMenu()
        let visibility = menu.addItem(withTitle: store.preferences.petVisible ? "지크 숨기기" : "지크 보이기", action: #selector(togglePetVisibility), keyEquivalent: "")
        visibility.target = self
        let settings = menu.addItem(withTitle: "설정…", action: #selector(openSettingsFromMenu), keyEquivalent: "")
        settings.target = self
        let dashboard = menu.addItem(withTitle: "상세 현황", action: #selector(showDashboard), keyEquivalent: "")
        dashboard.target = self
        if store.debugModeEnabled {
            let tests = menu.addItem(withTitle: "지크 모션 테스트…", action: #selector(showMotionTests), keyEquivalent: "")
            tests.target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "\(AppInfo.name) 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
    }
    // MARK: - 지크 현황 배치
    /// 지크 주변의 가용 공간을 계산해 간단 현황을 열고 다른 현황 창과 중복 표시되지 않게 한다.
    private func toggleFromPet() {
        if quickMenu.isShown { quickMenu.close(); return }
        dismissMenuAlert(); closeStatusPopovers()
        dashboardWindow?.orderOut(nil)
        quickMenu.show(store: store, anchor: pet.rabbitScreenFrame, screen: pet.visibleScreenFrame, petWindow: pet.panel, labelWidth: pet.quickMenuLabelWidth,
                       openTool: { tool in NSWorkspace.shared.open(tool.url) })
        pet.paused = true
        store.refreshForPresentation()
    }

    /// 원형 메뉴의 현황 항목에서 기존 간단 현황을 연다.
    private func showPetStatus() {
        dismissMenuAlert()
        dashboardWindow?.orderOut(nil)
        if petPopover.isShown { petPopover.performClose(nil); return }
        menuPopover.performClose(nil)
        guard let view = pet.panel.contentView else { return }
        pet.paused = true
        let anchor = pet.rabbitScreenFrame
        let placement = PopoverPlacement(anchor: anchor, visibleFrame: pet.visibleScreenFrame, preferredSize: PetStatusView.preferredSize)
        petPopover.contentViewController = NSHostingController(rootView: PetStatusView(store: store, showSettings: { [weak self] in self?.showSettings() }, size: placement.contentSize))
        petPopover.contentSize = placement.contentSize
        // NSHostingView는 뒤집힌 좌표계이므로 화면 위쪽은 minY에 해당한다.
        let edge: NSRectEdge
        switch placement.side {
        case .above: edge = view.isFlipped ? .minY : .maxY
        case .below: edge = view.isFlipped ? .maxY : .minY
        case .right: edge = .maxX
        case .left: edge = .minX
        }
        let rect = view.convert(pet.panel.convertFromScreen(anchor), from: nil)
        petPopover.show(relativeTo: rect, of: view, preferredEdge: edge)
        store.refreshForPresentation()
    }
    /// 팝오버 종료 시 공개 상태 조회와 산책 일시정지 상태를 정리한다.
    func popoverDidClose(_ notification: Notification) {
        if let popover = notification.object as? NSPopover, popover === menuPopover { serviceStatus.stop() }
        pet.paused = menuPopover.isShown || petPopover.isShown || quickMenu.isShown
    }
    /// 두 현황 팝오버를 함께 닫는다.
    private func closeStatusPopovers() {
        menuPopover.performClose(nil); petPopover.performClose(nil); quickMenu.close()
    }
    // MARK: - 설정과 디버그
    /// 설정 창을 한 번 생성해 재사용한다.
    private func showSettings() {
        dismissMenuAlert()
        closeStatusPopovers()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 700), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "\(AppInfo.name) 설정"; window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(BunnyTheme.background); window.titlebarAppearsTransparent = true
            window.contentView = NSHostingView(rootView: SettingsView(store: store, resetPosition: { [weak self] in self?.pet.resetPosition() }, loginItem: loginItem, showMotionTests: { [weak self] in self?.showMotionTests() }))
            window.center(); settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    /// 디버그 모드에서만 모션 테스트 창을 열고 지크 컨트롤러의 로컬 재생 동작에 연결한다.
    @objc private func showMotionTests() {
        guard store.debugModeEnabled else { return }
        dismissMenuAlert(); closeStatusPopovers()
        if motionTestWindow == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: MotionTestView.size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "지크 모션 테스트 · \(AppInfo.name)"; window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua); window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(BunnyTheme.background); window.delegate = self
            window.contentView = NSHostingView(rootView: MotionTestView(store: store, motion: pet.motion, run: { [weak self] action in self?.pet.runTest(action) }, stop: { [weak self] in self?.pet.stopTest() }, showMenuStatus: { [weak self] in self?.showMenuAlerts() }))
            window.center(); motionTestWindow = window
        }
        motionTestWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    /// 모션 테스트 창을 닫으면 진행 중인 테스트를 중단한다.
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === motionTestWindow { pet.stopTest() }
        if let window = notification.object as? NSWindow, window === resultWindow {
            window.contentView = nil
            store.webSession.webView.evaluateJavaScript("window.__zcreSupporterOutputAbort?.abort()", completionHandler: nil)
        }
    }
    /// 앱 메뉴와 로그인 입력란에서 사용할 기본 편집 명령을 등록한다.
    private func installMenu() {
        let menu = NSMenu()
        let root = NSMenuItem(); menu.addItem(root)
        let appMenu = NSMenu(); root.submenu = appMenu
        let dashboardItem = appMenu.addItem(withTitle: "현황 보기", action: #selector(showDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "\(AppInfo.name) 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); edit.title = "편집"; menu.addItem(edit)
        let editMenu = NSMenu(title: "편집"); edit.submenu = editMenu
        editMenu.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = menu
    }
    // MARK: - 시스템 생명주기
    /// Mac 잠자기 진입 시 데이터 조회·공개 상태 조회·모션과 배너를 중단한다.
    @objc private func willSleep() { closeStatusPopovers(); dismissMenuAlert(); serviceStatus.stop(); store.sleep(); pet.updatePreferences(); updateStatus() }
    /// Mac 깨우기 이후 데이터 조회와 필요한 화면 갱신을 재개한다.
    @objc private func didWake() { store.wake(); if menuPopover.isShown { serviceStatus.start() }; pet.updatePreferences(); updateStatus() }
    /// 동작 줄이기 설정 변경을 메뉴 막대 애니메이션에 반영한다.
    @objc private func accessibilityChanged() { updateStatus() }
    /// 디스플레이 구성이 바뀌면 팝오버를 닫고 완전히 화면 밖으로 사라진 지크만 복귀시킨다.
    @objc private func screensChanged() { dismissMenuAlert(); closeStatusPopovers(); pet.recoverPositionIfNeeded() }
    /// 앱이 활성화되면 로그인 항목과 macOS 알림 권한의 현재 상태를 다시 읽는다.
    func applicationDidBecomeActive(_ notification: Notification) {
        loginItem.refresh()
        Task { await store.refreshNotificationStatus() }
    }
    /// 이미 실행 중인 앱을 다시 열었을 때 기본 현황 창을 표시한다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPrimaryWindow()
        return false
    }
    /// 마지막 창을 닫아도 메뉴 막대에서 계정 감시를 계속한다.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    /// 종료 시 작업 타자 소리 등 반복 오디오를 정리한다.
    func applicationWillTerminate(_ notification: Notification) { quickMenu.close(); pet?.stopSounds() }
}
