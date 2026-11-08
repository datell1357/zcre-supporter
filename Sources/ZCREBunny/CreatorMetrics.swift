// 기능 분류: 필요한 프로필 요약값만 메모리에 보관 · 계정 경계 · 10분 캐시
import Foundation
import Observation
import ZCRECore

struct CreatorMetrics: Decodable, Equatable {
    struct Account: Decodable, Equatable {
        struct Day: Decodable, Equatable {
            let day: String
            let followers: Int64?
            var date: Date? { ISO8601DateFormatter().date(from: day + "T00:00:00Z") }
        }
        let daily: [Day]
        let trendUnavailable: Bool
        let platform: String
        let handle: String
        let followers: Int64?
        let change7d: Int64?
        let observedAt: Date?
        let status: String
        let derivedAvailable: Bool

        var platformName: String {
            switch platform { case "instagram": "Instagram"; case "tiktok": "TikTok"; case "youtube": "YouTube"; case "threads": "Threads"; default: platform }
        }
    }
    let totalFollowers: Int64?
    let change7d: Int64?
    let updatedAt: Date?
    let collectionPaused: Bool
    let accounts: [Account]

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 98_304 else { throw SnapshotError.invalidResponse }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: text) else { throw SnapshotError.invalidResponse }
            return date
        }
        let value = try decoder.decode(Self.self, from: data)
        let validNumber: (Int64?, Bool) -> Bool = { n, signed in
            guard let n else { return true }
            return n >= (signed ? -1_000_000_000_000 : 0) && n <= 1_000_000_000_000
        }
        guard value.accounts.count <= 32, validNumber(value.totalFollowers, false), validNumber(value.change7d, true),
              value.accounts.allSatisfy({ !$0.platform.isEmpty && $0.platform.count <= 32 && !$0.handle.isEmpty && $0.handle.count <= 128 && $0.status.count <= 40 && validNumber($0.followers, false) && validNumber($0.change7d, true) && $0.daily.count <= 32 && Set($0.daily.map(\.day)).count == $0.daily.count && $0.daily.allSatisfy { $0.day.count == 10 && $0.date != nil && validNumber($0.followers, false) } }) else { throw SnapshotError.invalidResponse }
        return value
    }
}

struct CreatorMetricsHTTPError: Error {
    let status: Int
    let retryAfter: TimeInterval
}

@MainActor @Observable
final class CreatorMetricsStore {
    private(set) var snapshot: CreatorMetrics?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    @ObservationIgnored var loader: ((String) async throws -> CreatorMetrics)?
    @ObservationIgnored var cancelRequest: (() -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var workspace: String?
    @ObservationIgnored private var demo = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var nextAllowed: TimeInterval = 0
    @ObservationIgnored private let uptime: () -> TimeInterval

    init(uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, loader: ((String) async throws -> CreatorMetrics)? = nil) {
        self.uptime = uptime; self.loader = loader
    }

    /// 계정·데모 전환 시 이전 응답과 캐시를 폐기한다. 디스크에는 저장하지 않는다.
    func setContext(workspace: String?, demo: Bool) {
        guard self.workspace != workspace || self.demo != demo else { return }
        stop(); self.workspace = workspace; self.demo = demo
        snapshot = nil; errorMessage = nil; nextAllowed = 0
    }

    var canRefresh: Bool { workspace != nil && !demo && !isRefreshing && uptime() >= nextAllowed }

    /// 탭을 열 때만 호출한다. 성공 후 10분, 실패 후 최소 60초는 다시 열어도 재요청하지 않는다.
    @discardableResult func refresh() -> Task<Void, Never>? {
        if let task { return task }
        guard canRefresh, let workspace, let loader else { return nil }
        let current = revision
        nextAllowed = uptime() + 60
        isRefreshing = true
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.revision == current { self.task = nil; self.isRefreshing = false } }
            do {
                let value = try await loader(workspace)
                guard !Task.isCancelled, self.revision == current else { return }
                self.snapshot = value; self.errorMessage = nil
                self.nextAllowed = self.uptime() + 600
            } catch {
                guard !Task.isCancelled, self.revision == current else { return }
                if let http = error as? CreatorMetricsHTTPError {
                    self.nextAllowed = self.uptime() + max(60, min(86400, http.retryAfter))
                    self.errorMessage = http.status == 401 ? "ZCRE 로그인을 다시 확인해 주세요." : http.status == 403 ? "ZCRE NEXT 이용 권한과 등록 상태를 확인해 주세요." : "프로필 메트릭을 가져오지 못했어요. 잠시 후 다시 확인해 주세요."
                } else { self.errorMessage = "프로필 메트릭을 가져오지 못했어요. 잠시 후 다시 확인해 주세요." }
            }
        }
        return task
    }

    /// 탭이 숨겨지거나 잠자기에 들어가면 요청을 중단하고 기존 캐시·재시도 제한은 유지한다.
    func stop() {
        revision += 1; task?.cancel(); task = nil; isRefreshing = false; cancelRequest?()
    }
}

extension WebSession {
    /// 인증은 기존 WebKit 안에 유지하고 최소 JSON만 네이티브로 반환한다.
    func creatorMetrics(workspace: String) async throws -> CreatorMetrics {
        guard isLoaded, let url = Bundle.module.url(forResource: "ReadCreatorMetrics", withExtension: "js") else { throw SnapshotError.network }
        let script = try String(contentsOf: url, encoding: .utf8)
        let value = try await webView.callAsyncJavaScript(script, arguments: ["workspaceKey": workspace], in: nil, contentWorld: .page)
        try Task.checkCancellation()
        guard let json = value as? String, let data = json.data(using: .utf8), data.count <= 98_304,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SnapshotError.invalidResponse }
        if let status = object["error"] as? Int {
            throw CreatorMetricsHTTPError(status: status, retryAfter: HTTPRetryAfter.seconds(object["retryAfter"] as? String, relativeTo: .now))
        }
        guard let metrics = object["metrics"], JSONSerialization.isValidJSONObject(metrics) else { throw SnapshotError.invalidResponse }
        return try CreatorMetrics.decode(JSONSerialization.data(withJSONObject: metrics))
    }
}
