// 기능 분류: GitHub 배포본 업데이트 감지 · 설치 파일 무결성 확인 · 스토어 경로 분리
import AppKit
import CryptoKit
import Foundation
import Observation
import ZCRECore
#if canImport(Sparkle)
import Sparkle
#endif

struct AppRelease: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        let name: String
        let size: Int64
        let digest: String?
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey { case name, size, digest; case browserDownloadURL = "browser_download_url" }
    }
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    enum CodingKeys: String, CodingKey { case draft, prerelease, assets; case tagName = "tag_name" }

    // 정식 숫자 버전만 비교한다. 같은 버전의 재업로드·시험판으로 자동 전환하지 않는다.
    static func version(_ text: String) -> [Int]? {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == 3 ? numbers : nil
    }
    func isNewer(than current: String) -> Bool {
        guard !draft, !prerelease, let candidate = Self.version(tagName), let installed = Self.version(current) else { return false }
        return installed.lexicographicallyPrecedes(candidate)
    }
    /// 다운로드가 끝난 파일을 작은 청크로 검사한다. 크기/해시가 다르면 설치에 사용하지 않는다.
    static func verifyInstaller(_ url: URL, asset: Asset) throws -> Bool {
        let bytes = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        guard bytes?.int64Value == asset.size, let digest = asset.digest, digest.hasPrefix("sha256:"), digest.count == 71 else { return false }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation(); hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined() == String(digest.dropFirst(7)).lowercased()
    }
    func macAsset(architecture: String) -> Asset? {
        assets.filter { asset in
            let url = asset.browserDownloadURL
            let digest = asset.digest ?? ""
            return asset.name.hasPrefix("ZCRE-Supporter-") && asset.name.contains("-macOS-") && asset.name.hasSuffix(".dmg") &&
                (asset.name.contains("-universal") || asset.name.contains("-\(architecture)")) &&
                asset.size > 0 && asset.size <= 1_073_741_824 && digest.hasPrefix("sha256:") && digest.count == 71 &&
                digest.dropFirst(7).allSatisfy({ $0.isASCII && $0.isHexDigit }) &&
                url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil &&
                url.path.hasPrefix("/datell1357/zcre-supporter/releases/download/\(tagName)/") && url.lastPathComponent == asset.name
        }.sorted { ($0.name.contains("-universal") ? 0 : 1) < ($1.name.contains("-universal") ? 0 : 1) }.first
    }
}

@MainActor @Observable
final class AppUpdateStore {
    static let releasesURL = URL(string: "https://github.com/datell1357/zcre-supporter/releases/latest")!
    let isAppStore: Bool
    var automatic: Bool {
        didSet {
            defaults.set(automatic, forKey: "automaticUpdateChecks")
            if automatic { start() } else { loop?.cancel(); loop = nil }
        }
    }
    private(set) var release: AppRelease?
    private(set) var isChecking = false
    private(set) var message = "새 버전은 12시간 간격으로 확인해요"
    @ObservationIgnored private let currentVersion: String
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loop: Task<Void, Never>?
    #if canImport(Sparkle)
    @ObservationIgnored private var updaterController: SPUStandardUpdaterController?
    #endif
    @ObservationIgnored private var nextCheck = Date.distantPast
    @ObservationIgnored var networkAvailable: () -> Bool = { true }
    @ObservationIgnored var didFindUpdate: (() -> Void)?

    init(defaults: UserDefaults = .standard, isAppStore: Bool? = nil, currentVersion: String = AppInfo.version) {
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.isAppStore = isAppStore ?? (Bundle.main.object(forInfoDictionaryKey: "ZCREDistribution") as? String == "app-store" || Bundle.main.appStoreReceiptURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        automatic = defaults.object(forKey: "automaticUpdateChecks") as? Bool ?? true
        if self.isAppStore { message = "App Store에서 업데이트를 관리해요" }
    }
    var asset: AppRelease.Asset? {
        #if arch(arm64)
        release?.macAsset(architecture: "arm64")
        #else
        release?.macAsset(architecture: "x86_64")
        #endif
    }
    /// 시작 시 한 번, 이후 12시간마다 확인한다. 계정·작업 정보는 보내지 않는다.
    func start() {
        guard !isAppStore, automatic, loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                do { try await Task.sleep(for: .seconds(43_200)) } catch { return }
            }
        }
    }
    func stop() { loop?.cancel(); loop = nil }

    func check() async {
        guard !isAppStore, !isChecking, networkAvailable(), Date.now >= nextCheck else { return }
        isChecking = true; nextCheck = .now.addingTimeInterval(60)
        defer { isChecking = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/datell1357/zcre-supporter/releases/latest")!)
            request.timeoutInterval = 20
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 403 || http.statusCode == 429 {
                let retry = HTTPRetryAfter.seconds(http.value(forHTTPHeaderField: "Retry-After"), relativeTo: .now)
                nextCheck = .now.addingTimeInterval(max(3600, min(86400, retry)))
                throw URLError(.resourceUnavailable)
            }
            guard http.statusCode == 200, data.count <= 1_048_576 else { throw URLError(.badServerResponse) }
            let value = try JSONDecoder().decode(AppRelease.self, from: data)
            nextCheck = .now.addingTimeInterval(43_200)
            if value.isNewer(than: currentVersion) {
                let changed = release?.tagName != value.tagName
                release = value
                message = "\(value.tagName) 업데이트가 있어요"
                if changed { didFindUpdate?() }
            } else { release = nil; message = "최신 버전을 사용 중이에요 · \(currentVersion)" }
        } catch is CancellationError { }
        catch { message = "업데이트를 확인하지 못했어요 · 잠시 후 다시 시도해 주세요" }
    }
    /// 설치는 Sparkle이 서명 검증·앱 교체·재실행까지 수행한다. 사용자가 누르기 전에는 실행하지 않는다.
    func installUpdate() {
        guard !isAppStore, networkAvailable() else { return }
        #if canImport(Sparkle)
        if updaterController == nil {
            updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }
        guard let updaterController, updaterController.updater.canCheckForUpdates else { return }
        updaterController.checkForUpdates(nil)
        #endif
    }
    func openDistribution() {
        NSWorkspace.shared.open(isAppStore ? URL(string: "macappstore://showUpdatesPage")! : Self.releasesURL)
    }
}
