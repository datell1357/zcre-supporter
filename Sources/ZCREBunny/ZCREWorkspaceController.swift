// 기능 분류: ZCRE 작업 창 · 모든 도구를 앱 안 한 창에서 전환 · 웹 저장 세션 · 파일 선택과 다운로드
import AppKit
import WebKit

/// 지크 메뉴·상단 바·현황판에서 고른 ZCRE 도구와 ZCUT을 앱 안의 한 창에서 연다.
/// 이미 열린 창이 있으면 새 창을 만들지 않고 같은 창의 화면만 전환한다.
/// 기본 웹 저장소를 계정 연결 세션과 공유하므로 따로 로그인할 필요가 없고,
/// 업로드·팝업·저장·다운로드는 macOS 창으로 처리한다.
@MainActor
final class ZCREWorkspaceController: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, NSWindowDelegate, NSToolbarDelegate, NSToolbarItemValidation {
    static let shared = ZCREWorkspaceController()
    static let home = URL(string: "https://www.zcre.co.kr/")!
    /// 작업 창에서 시작할 수 있는 공식 주소. 그 밖의 주소는 기본 브라우저로 넘긴다.
    static let allowedHosts: Set<String> = ["www.zcre.co.kr", "zcre.co.kr", "zcut.ai", "www.zcut.ai"]

    private var window: NSWindow?
    private var webView: WKWebView?
    private var popups: [ObjectIdentifier: NSWindow] = [:]
    private var windowByWebView: [ObjectIdentifier: NSWindow] = [:]
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    /// 현재 화면의 도구. 창 제목과 도구 메뉴의 선택 표시에 쓴다.
    private(set) var currentTool: ZCREQuickTool?
    private var currentTitle = "ZCRE"
    private var toolMenuItem: NSMenuToolbarItem?

    var isShown: Bool { window?.isVisible == true }

    // MARK: - 화면 열기와 전환
    /// 원형 메뉴의 도구를 연다. 창이 열려 있으면 같은 창에서 해당 도구로 전환한다.
    func show(tool: ZCREQuickTool) {
        currentTool = tool
        open(tool.url, title: tool.title)
    }

    /// 현황판·알림·결과 링크처럼 도구가 아닌 ZCRE 화면을 같은 작업 창에서 연다.
    func show(url: URL, title: String = "ZCRE") {
        guard Self.isAllowedStart(url) else { NSWorkspace.shared.open(url); return }
        currentTool = ZCREQuickTool.allCases.first { $0.url == url }
        open(url, title: currentTool?.title ?? title)
    }

    private func open(_ url: URL, title: String) {
        currentTitle = title
        if window == nil { makeWindow() }
        if webView?.url != url { webView?.load(URLRequest(url: url)) }
        updateChrome()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func isAllowedStart(_ url: URL) -> Bool {
        url.scheme == "https" && allowedHosts.contains(url.host?.lowercased() ?? "")
    }

    private func makeWindow() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        if let url = Bundle.module.url(forResource: "ZCUTExportBridge", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            configuration.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        let browser = WKWebView(frame: .zero, configuration: configuration)
        browser.navigationDelegate = self
        browser.uiDelegate = self
        browser.allowsBackForwardNavigationGestures = true
        browser.allowsMagnification = true

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "ZCRE 서포터"
        panel.minSize = NSSize(width: 900, height: 620)
        panel.setFrameAutosaveName("ZCREWorkspaceWindow")
        let toolbar = NSToolbar(identifier: "ZCREWorkspaceToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        panel.toolbar = toolbar
        panel.toolbarStyle = .unified
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = browser
        if panel.frame.origin == .zero { panel.center() }

        window = panel
        webView = browser
        windowByWebView[ObjectIdentifier(browser)] = panel
    }

    /// 창 제목과 도구 메뉴의 체크 표시를 현재 화면에 맞춘다.
    private func updateChrome() {
        window?.title = "\(currentTitle) · ZCRE 서포터"
        window?.toolbar?.validateVisibleItems()
        toolMenuItem?.menu = makeToolMenu()
        toolMenuItem?.title = currentTool?.title ?? "도구 선택"
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === self.webView {
            // 웹 안에서 다른 도구로 이동하면 메뉴 선택도 따라간다.
            if let url = webView.url, let tool = ZCREQuickTool.matching(url) {
                currentTool = tool
                currentTitle = tool.title
            } else if currentTool != nil, webView.url.flatMap(ZCREQuickTool.matching) == nil {
                currentTool = nil
                let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                currentTitle = title.isEmpty ? "ZCRE" : title
            }
            updateChrome()
            return
        }
        let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        windowByWebView[ObjectIdentifier(webView)]?.title = title.isEmpty ? "로그인 · ZCRE 서포터" : "\(title) · ZCRE 서포터"
    }

    // MARK: - 상단 도구 막대 (뒤로·앞으로·새로고침·도구 전환·브라우저로 열기)
    private enum ToolbarID {
        static let back = NSToolbarItem.Identifier("workspace.back")
        static let forward = NSToolbarItem.Identifier("workspace.forward")
        static let reload = NSToolbarItem.Identifier("workspace.reload")
        static let tools = NSToolbarItem.Identifier("workspace.tools")
        static let external = NSToolbarItem.Identifier("workspace.external")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.back, ToolbarID.forward, ToolbarID.reload, .flexibleSpace, ToolbarID.tools, .flexibleSpace, ToolbarID.external]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func button(_ symbol: String, _ label: String, _ action: Selector) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            item.label = label
            item.toolTip = label
            item.target = self
            item.action = action
            item.isBordered = true
            return item
        }
        switch itemIdentifier {
        case ToolbarID.back: return button("chevron.left", "뒤로", #selector(goBack))
        case ToolbarID.forward: return button("chevron.right", "앞으로", #selector(goForward))
        case ToolbarID.reload: return button("arrow.clockwise", "새로고침", #selector(reloadPage))
        case ToolbarID.external: return button("safari", "브라우저로 열기", #selector(openInBrowser))
        case ToolbarID.tools:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "도구 전환"
            item.title = currentTool?.title ?? "도구 선택"
            item.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "도구 전환")
            item.showsIndicator = true
            item.menu = makeToolMenu()
            toolMenuItem = item
            return item
        default: return nil
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case ToolbarID.back: webView?.canGoBack == true
        case ToolbarID.forward: webView?.canGoForward == true
        case ToolbarID.reload, ToolbarID.external: webView?.url != nil
        default: true
        }
    }

    /// 지크 원형 메뉴와 같은 분류로 도구를 묶어 창 안에서 바로 전환한다.
    private func makeToolMenu() -> NSMenu {
        let menu = NSMenu()
        for group in ZCREQuickTool.groups {
            let header = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for tool in group.tools {
                let item = NSMenuItem(title: tool.title, action: #selector(selectTool(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = tool.rawValue
                item.image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: nil)
                item.state = tool == currentTool ? .on : .off
                item.indentationLevel = 1
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        let home = NSMenuItem(title: "ZCRE 홈", action: #selector(showHome), keyEquivalent: "")
        home.target = self
        menu.addItem(home)
        return menu
    }

    @objc private func selectTool(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tool = ZCREQuickTool(rawValue: raw) else { return }
        show(tool: tool)
    }

    @objc private func showHome() { show(url: Self.home, title: "ZCRE") }
    @objc private func goBack() { webView?.goBack() }
    @objc private func goForward() { webView?.goForward() }
    @objc private func reloadPage() { webView?.reload() }
    @objc private func openInBrowser() {
        if let url = webView?.url, url.scheme == "https" { NSWorkspace.shared.open(url) }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        window?.toolbar?.validateVisibleItems()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        guard let url = navigationAction.request.url else { return (.cancel, preferences) }
        if navigationAction.shouldPerformDownload { return (.download, preferences) }
        if Self.isDownloadURL(url) { return (.download, preferences) }
        if url.scheme == "https" || url.scheme == "http" || url.absoluteString == "about:blank" {
            return (.allow, preferences)
        }
        if url.scheme == "mailto" { NSWorkspace.shared.open(url) }
        return (.cancel, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if let response = navigationResponse.response as? HTTPURLResponse,
           response.value(forHTTPHeaderField: "Content-Disposition")?.lowercased().contains("attachment") == true {
            return .download
        }
        if navigationResponse.canShowMIMEType { return .allow }
        return .download
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    /// 웹 페이지의 파일 선택 입력을 macOS 파일 고르기 창과 연결한다.
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.title = "ZCRE에 올릴 파일 선택"
        present(panel) { result in
            completionHandler(result == .OK ? panel.urls : nil)
        }
    }

    /// ZIP·MP4처럼 WebKit이 직접 표시하지 않는 응답과 웹 다운로드를 사용자 저장 위치로 받는다.
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let panel = NSSavePanel()
        panel.title = "결과 저장"
        panel.nameFieldStringValue = Self.safeFilename(suggestedFilename)
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        let result = await withCheckedContinuation { continuation in
            present(panel) { response in continuation.resume(returning: response) }
        }
        let destination = result == .OK ? panel.url : nil
        if let destination {
            let key = ObjectIdentifier(download)
            downloadDestinations[key] = destination
        }
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        guard let destination = downloadDestinations.removeValue(forKey: key) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let key = ObjectIdentifier(download)
        downloadDestinations.removeValue(forKey: key)
    }

    /// ZCUT·ZCRE 로그인처럼 새 창을 요청하는 링크는 같은 저장소를 쓰는 앱 내부 창으로 연다.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        configuration.websiteDataStore = .default()
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "로그인 · ZCRE 서포터"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = popup
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        let key = ObjectIdentifier(popup)
        popups[key] = panel
        windowByWebView[key] = panel
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        popups[ObjectIdentifier(webView)]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if closing === window {
            if let webView { windowByWebView.removeValue(forKey: ObjectIdentifier(webView)) }
            webView?.navigationDelegate = nil
            webView?.uiDelegate = nil
            webView = nil
            window = nil
            popups.values.forEach { $0.close() }
            popups.removeAll()
            toolMenuItem = nil
            currentTool = nil
            return
        }
        for (key, popup) in popups where popup === closing {
            popups.removeValue(forKey: key)
            windowByWebView.removeValue(forKey: key)
            break
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = currentTitle
        alert.informativeText = message
        alert.addButton(withTitle: "확인")
        present(alert) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = currentTitle
        alert.informativeText = message
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        present(alert) { response in completionHandler(response == .alertFirstButtonReturn) }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        present(alert) { response in
            completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    /// 앱에 붙은 창이 있으면 시트로, 그 밖의 상황에서는 앱 모달로 표시한다.
    private func present(_ panel: NSSavePanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { completion(panel.runModal()) }
    }

    private func present(_ panel: NSOpenPanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { completion(panel.runModal()) }
    }

    private func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window { alert.beginSheetModal(for: window, completionHandler: completion) }
        else { completion(alert.runModal()) }
    }

    private static func safeFilename(_ suggested: String) -> String {
        let name = URL(fileURLWithPath: suggested).lastPathComponent
        return name.isEmpty ? "ZCRE 결과" : name
    }

    /// 서명 URL의 attachment 지시나 ZCUT 클라우드의 영상 확장자를 다운로드로 처리한다.
    static func isDownloadURL(_ url: URL) -> Bool {
        let query = url.query?.lowercased() ?? ""
        let mediaExtension = ["mp4", "mov", "m4v", "webm", "zip"].contains(url.pathExtension.lowercased())
        return query.contains("response-content-disposition=attachment")
            || (mediaExtension && url.host?.contains(".amazonaws.com") == true)
    }
}
