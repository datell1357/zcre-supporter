import Foundation
import Testing
@testable import ZCREBunny

@Suite struct AppUpdateTests {
    private func release(_ version: String = "v0.0.4", url: String? = nil, name: String = "ZCRE-Supporter-0.0.4-macOS-universal.dmg", digest: String = "sha256:" + String(repeating: "a", count: 64), draft: Bool = false, prerelease: Bool = false) throws -> AppRelease {
        let object: [String: Any] = ["tag_name": version, "draft": draft, "prerelease": prerelease,
            "assets": [["name":name, "size":100, "digest":digest, "browser_download_url": url ?? "https://github.com/datell1357/zcre-supporter/releases/download/\(version)/\(name)"]]]
        return try JSONDecoder().decode(AppRelease.self, from: JSONSerialization.data(withJSONObject: object))
    }
    @Test func stableVersionsOnlyAndNoDowngrade() throws {
        #expect(try release().isNewer(than: "0.0.3"))
        #expect(try release("v0.4.1").isNewer(than: "0.0.4"))
        #expect(try release("v0.10.0").isNewer(than: "0.9.9"))
        #expect(try !release("v0.0.3").isNewer(than: "0.0.3"))
        #expect(try !release("v0.0.2").isNewer(than: "0.0.3"))
        #expect(try !release("v1.0.0-beta").isNewer(than: "0.0.3"))
        #expect(try !release(draft: true).isNewer(than: "0.0.3"))
        #expect(try !release(prerelease: true).isNewer(than: "0.0.3"))
        #expect(AppRelease.version("1..2") == nil)
        #expect(AppRelease.version("１.２.３") == nil)
    }
    @Test func installAssetsMustMatchRepositoryPlatformArchitectureAndDigest() throws {
        #expect(try release().macAsset(architecture: "arm64") != nil)
        #expect(try release(name: "ZCRE-Supporter-0.0.4-Windows-x64.msi").macAsset(architecture: "arm64") == nil)
        #expect(try release(name: "ZCRE-Supporter-0.0.4-macOS-x86_64.dmg").macAsset(architecture: "arm64") == nil)
        #expect(try release(url: "https://github.com/other/repo/releases/download/v0.0.4/ZCRE-Supporter-0.0.4-macOS-universal.dmg").macAsset(architecture: "arm64") == nil)
        #expect(try release(url: "http://github.com/datell1357/zcre-supporter/releases/download/v0.0.4/ZCRE-Supporter-0.0.4-macOS-universal.dmg").macAsset(architecture: "arm64") == nil)
        #expect(try release(digest: "sha256:bad").macAsset(architecture: "arm64") == nil)
        #expect(try release(digest: "sha256:" + String(repeating: "g", count:64)).macAsset(architecture: "arm64") == nil)
    }
    @Test func rejectsTruncatedAndTamperedInstaller() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("test.dmg")
        let asset = AppRelease.Asset(name: "test.dmg", size: 3, digest: "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", browserDownloadURL: URL(string: "https://github.com")!)
        try Data("abc".utf8).write(to: file)
        #expect(try AppRelease.verifyInstaller(file, asset: asset))
        try Data("abd".utf8).write(to: file)
        #expect(try !AppRelease.verifyInstaller(file, asset: asset))
        try Data("ab".utf8).write(to: file)
        #expect(try !AppRelease.verifyInstaller(file, asset: asset))
    }
    // 명시한 경우에만 실제 공개 릴리즈를 다운로드한다. 설치·실행·앱 교체는 하지 않는다.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ZCRE_LIVE_UPDATE_TEST"] == "1"))
    @MainActor func officialReleaseDownload() async throws {
        let name = "UpdateDownloadTest-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let installed = ProcessInfo.processInfo.environment["ZCRE_TEST_INSTALLED_VERSION"] ?? "0.0.0"
        let store = AppUpdateStore(defaults: defaults, isAppStore: false, currentVersion: installed)
        await store.check()
        if let expected = ProcessInfo.processInfo.environment["ZCRE_EXPECTED_UPDATE_TAG"] {
            #expect(store.release?.tagName == expected)
        }
        #expect(store.release != nil)
        #expect(store.asset != nil)
        store.downloadUpdate()
        let timeout = Date.now.addingTimeInterval(330)
        while store.isDownloading && Date.now < timeout { try await Task.sleep(for: .milliseconds(100)) }
        defer { store.stop() }
        let installer = try #require(store.installer)
        defer { try? FileManager.default.removeItem(at: installer.deletingLastPathComponent()) }
        #expect(try AppRelease.verifyInstaller(installer, asset: #require(store.asset)))
        let quarantine = try (installer as NSURL).resourceValues(forKeys: [.quarantinePropertiesKey])
        #expect(quarantine[.quarantinePropertiesKey] != nil)
    }
    @Test @MainActor func appStoreNeverChecksOrDownloadsFromGitHub() async {
        let name = "UpdateTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppUpdateStore(defaults: defaults, isAppStore: true)
        var networkChecks = 0
        store.networkAvailable = { networkChecks += 1; return true }
        store.start(); await store.check(); store.downloadUpdate()
        #expect(networkChecks == 0)
        #expect(store.release == nil)
        #expect(!store.isDownloading)
        #expect(store.message.contains("App Store"))
        store.stop()
    }
}
