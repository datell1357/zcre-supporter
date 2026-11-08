// 기능 분류: GitHub 배포본 업데이트 감지 · 설치 파일 무결성 확인 · 스토어 경로 분리
import AppKit
import CryptoKit
import Foundation
import Observation
import ZCRECore

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
    private(set) var isDownloading = false
    private(set) var installer: URL?
    private(set) var message = "새 버전은 12시간 간격으로 확인해요"
    @ObservationIgnored private let currentVersion: String
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var download: Task<Void, Never>?
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
    func stop() { loop?.cancel(); loop = nil; download?.cancel(); download = nil }

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
                if changed { installer = nil }
                release = value
                message = "\(value.tagName) 업데이트가 있어요"
                if changed { didFindUpdate?() }
            } else { release = nil; installer = nil; message = "최신 버전을 사용 중이에요 · \(currentVersion)" }
        } catch is CancellationError { }
        catch { message = "업데이트를 확인하지 못했어요 · 잠시 후 다시 시도해 주세요" }
    }
    /// 명시적으로 누른 경우에만 다운로드한다. 파일을 교체하거나 실행 중 앱을 강제 종료하지 않는다.
    func downloadUpdate() {
        guard !isAppStore, !isDownloading, let asset else { return }
        isDownloading = true; message = "업데이트 다운로드 및 무결성 확인 중…"
        download = Task { [weak self] in
            guard let self else { return }
            defer { self.isDownloading = false; self.download = nil }
            do {
                var request = URLRequest(url: asset.browserDownloadURL); request.timeoutInterval = 300
                let (temporary, response) = try await URLSession.shared.download(for: request)
                defer { try? FileManager.default.removeItem(at: temporary) }
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let final = http.url, final.scheme == "https", ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(final.host ?? "") else { throw URLError(.badServerResponse) }
                // 해시는 백그라운드에서 청크 단위로 계산해 화면/모션을 막지 않는다.
                let valid = try await Task.detached(priority: .utility) {
                    try AppRelease.verifyInstaller(temporary, asset: asset)
                }.value
                try Task.checkCancellation()
                guard valid else { throw URLError(.cannotDecodeContentData) }
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ZCRE-Update-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let target = folder.appendingPathComponent(asset.name)
                try FileManager.default.moveItem(at: temporary, to: target)
                // OS의 다운로드 출처 검사도 유지한다. 해시 검증을 Gatekeeper 대체로 사용하지 않는다.
                try (target as NSURL).setResourceValue([
                    "LSQuarantineType": "LSQuarantineTypeWebDownload",
                    "LSQuarantineAgentName": AppInfo.name,
                    "LSQuarantineDataURL": asset.browserDownloadURL,
                    "LSQuarantineOriginURL": Self.releasesURL
                ], forKey: .quarantinePropertiesKey)
                self.installer = target; self.message = "검증 완료 · 설치 파일을 열어 Applications의 앱을 교체해 주세요"
            } catch is CancellationError { self.message = "업데이트 다운로드가 취소됐어요" }
            catch { self.message = "다운로드 또는 무결성 확인에 실패했어요 · 기존 앱은 유지돼요" }
        }
    }
    func openInstaller() { if let installer { NSWorkspace.shared.open(installer) } }
    func openDistribution() {
        NSWorkspace.shared.open(isAppStore ? URL(string: "macappstore://showUpdatesPage")! : Self.releasesURL)
    }
}
