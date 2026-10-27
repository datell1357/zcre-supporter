// 기능 분류: 서버 데이터 검증 · 작업 상태와 크레딧 공통 모델
import Foundation

public enum JobStatus: String, Codable, Sendable {
    case queued, running, succeeded, failed, cancelled, unknown

    /// 서버 상태 별칭을 공통 상태로 바꾸며 알 수 없는 상태는 성공이나 진행 중으로 추정하지 않는다.
    public init(serverValue: String) {
        switch serverValue.lowercased() {
        case "pending", "queued", "accepted", "submitted", "waiting", "received", "validated", "queued_internal": self = .queued
        case "running", "processing", "in_progress", "generating", "submitting_provider", "submitted_provider", "running_provider", "asset_ingesting": self = .running
        case "succeeded", "completed", "complete", "success": self = .succeeded
        case "failed", "error", "timeout", "timed_out": self = .failed
        case "cancelled", "canceled": self = .cancelled
        default: self = .unknown
        }
    }

    public var isActive: Bool { self == .queued || self == .running }
    public var isTerminal: Bool { self == .succeeded || self == .failed || self == .cancelled }
    public var label: String {
        switch self {
        case .queued: "대기 중"
        case .running: "만드는 중"
        case .succeeded: "완료"
        case .failed: "실패"
        case .cancelled: "취소됨"
        case .unknown: "상태 확인 중"
        }
    }
}

public struct GenerationJob: Identifiable, Equatable, Sendable {
    public let id: String
    public let model: String
    public let mediaType: String
    public let status: JobStatus
    public let createdAt: Date

    /// 표시에 필요한 작업 메타데이터만 보관한다.
    public init(id: String, model: String, mediaType: String, status: JobStatus, createdAt: Date) {
        self.id = id; self.model = model; self.mediaType = mediaType
        self.status = status; self.createdAt = createdAt
    }

    public var displayName: String {
        switch model {
        case "seedance-2.5": "Seedance 2.5"
        case "seedance-2", "seedance-2.0": "Seedance 2.0"
        case "gpt-image-2": "GPT Image 2"
        case "bytedance-upscale-video": "영상 업스케일"
        case "topaz-upscale-video-precision": "Topaz 영상 업스케일"
        default: model.replacingOccurrences(of: "-", with: " ")
        }
    }
    public var symbol: String {
        switch mediaType { case "video": "film"; case "audio": "waveform"; default: "photo" }
    }
    public var workName: String {
        if displayName.contains("업스케일") { return displayName }
        let type = switch mediaType { case "video": "영상"; case "audio": "오디오"; default: "이미지" }
        return "\(displayName) \(type)"
    }
    public var startTimeLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: createdAt)
    }
    // 알림에 모델·매체 이름을 넣어 어떤 작업이 끝났는지 구분한다.
    public var completionTitle: String { "\(workName) 완료" }
    public var completionBubble: String { "\(workName)\n\(startTimeLabel) 시작 · 작업 완료" }
    public var completionBody: String { "\(startTimeLabel)에 시작한 작업이 완료됐어요. ZCRE에서 결과를 확인해 보세요." }
}

public struct CreditBalance: Equatable, Sendable {
    public let total: Decimal
    public let reserved: Decimal
    public let available: Decimal
    /// 크레딧 소수 정밀도를 유지하도록 Decimal 값으로 잔액을 보관한다.
    public init(total: Decimal, reserved: Decimal, available: Decimal) {
        self.total = total; self.reserved = reserved; self.available = available
    }
    /// 크레딧을 한국어 숫자 형식과 소수 두 자리 이내로 표시한다.
    public static func format(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }
}

public struct ConcurrentWork: Codable, Equatable, Sendable {
    public let imagesActive: Int
    public let imagesLimit: Int
    public let videosActive: Int
    public let videosLimit: Int
    public let totalActive: Int
    public let totalLimit: Int
    public var isValid: Bool {
        [imagesActive, videosActive, totalActive].allSatisfy { $0 >= 0 } &&
        [imagesLimit, videosLimit, totalLimit].allSatisfy { $0 > 0 }
    }
}

public struct WorkspaceSnapshot: Equatable, Sendable {
    public let workspaceKey: String
    public let workspaceName: String
    public let balance: CreditBalance
    public let jobs: [GenerationJob]
    // 스냅샷은 불변이므로 진행 목록을 한 번만 계산해 모션 프레임마다 필터링하지 않는다.
    public let activeJobs: [GenerationJob]
    public let fetchedAt: Date
    public let balanceFetchedAt: Date
    public let balanceIsStale: Bool
    public let historyTruncated: Bool
    public let concurrency: ConcurrentWork?
    /// 모든 화면의 진행 개수를 동일한 작업 목록에서 계산한다. 웹 DOM에서는 요금제 한도만 사용한다.
    public init(workspaceKey: String, workspaceName: String, balance: CreditBalance, jobs: [GenerationJob], fetchedAt: Date, historyTruncated: Bool = false, concurrency: ConcurrentWork? = nil, balanceFetchedAt: Date? = nil, balanceIsStale: Bool = false) {
        self.workspaceKey = workspaceKey; self.workspaceName = workspaceName
        self.balance = balance; self.jobs = jobs; self.fetchedAt = fetchedAt; self.historyTruncated = historyTruncated
        self.activeJobs = jobs.filter { $0.status.isActive }
        self.balanceFetchedAt = balanceFetchedAt ?? fetchedAt; self.balanceIsStale = balanceIsStale
        // 숨겨진 계정 페이지에는 오래된 사용 개수가 남을 수 있다.
        // 웹에서는 요금제 한도만 사용하고 모든 화면의 사용 개수는 API 작업으로 계산한다.
        if let limits = concurrency, limits.isValid {
            let active = self.activeJobs
            self.concurrency = ConcurrentWork(
                imagesActive: active.filter { $0.mediaType == "image" }.count, imagesLimit: limits.imagesLimit,
                videosActive: active.filter { $0.mediaType == "video" }.count, videosLimit: limits.videosLimit,
                totalActive: active.count, totalLimit: limits.totalLimit)
        } else { self.concurrency = nil }
    }
}

public enum SnapshotError: Error, Equatable, LocalizedError {
    case authentication, accountChanged, invalidResponse, unsupportedWorkspace, network, http(Int)
    public var errorDescription: String? {
        switch self {
        case .authentication: "ZCRE에 로그인하면 현황을 가져올 수 있어요."
        case .accountChanged: "워크스페이스가 바뀌었어요. 다시 확인할게요."
        case .invalidResponse: "ZCRE 응답 형식을 확인할 수 없어요. 잠시 후 다시 시도해 주세요."
        case .unsupportedWorkspace: "크레딧을 사용하는 개인 워크스페이스를 선택해 주세요."
        case .network: "연결이 잠시 끊겼어요. 자동으로 다시 확인할게요."
        case .http(let code): "ZCRE 조회가 지연되고 있어요. (\(code))"
        }
    }
}

public enum SnapshotDecoder {
    private struct Payload: Decodable {
        let error: String?
        let status: Int?
        let workspaceKey: String?
        let workspaceName: String?
        let balance: Balance?
        let balanceFetchedAt: Double?
        let balanceIsStale: Bool?
        let jobs: [Job]?
        let historyTruncated: Bool?
        let concurrency: ConcurrentWork?
        struct Balance: Decodable { let total: String; let reserved: String; let available: String }
        struct Job: Decodable {
            let id: String; let model: String; let mediaType: String; let status: String; let createdAt: String
        }
    }
    /// 필수 필드·숫자·시각을 검증하고 잘못된 데이터나 인증 오류를 정상적인 0 잔액으로 표시하지 않는다.
    public static func decode(_ data: Data, now: Date = .now) throws -> WorkspaceSnapshot {
        guard let p = try? JSONDecoder().decode(Payload.self, from: data) else { throw SnapshotError.invalidResponse }
        if let error = p.error {
            switch error {
            case "authentication": throw SnapshotError.authentication
            case "accountChanged": throw SnapshotError.accountChanged
            case "unsupportedWorkspace": throw SnapshotError.unsupportedWorkspace
            case "http": throw SnapshotError.http(p.status ?? 0)
            case "network": throw SnapshotError.network
            default: throw SnapshotError.invalidResponse
            }
        }
        let locale = Locale(identifier: "en_US_POSIX")
        guard let key = p.workspaceKey, !key.isEmpty, let b = p.balance,
              [b.total, b.reserved, b.available].allSatisfy({ $0.range(of: #"^-?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil }),
              let total = Decimal(string: b.total, locale: locale),
              let reserved = Decimal(string: b.reserved, locale: locale),
              let available = Decimal(string: b.available, locale: locale),
              !total.isNaN, !reserved.isNaN, !available.isNaN, reserved >= 0,
              let rawJobs = p.jobs else { throw SnapshotError.invalidResponse }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        var seen = Set<String>()
        let jobs = try rawJobs.compactMap { job -> GenerationJob? in
            guard !job.id.isEmpty, !job.model.isEmpty,
                  let createdAt = fractional.date(from: job.createdAt) ?? plain.date(from: job.createdAt) else {
                throw SnapshotError.invalidResponse
            }
            guard seen.insert(job.id).inserted else { return nil }
            return GenerationJob(id: job.id, model: job.model, mediaType: job.mediaType, status: JobStatus(serverValue: job.status), createdAt: createdAt)
        }.sorted { $0.createdAt > $1.createdAt }
        if let time = p.balanceFetchedAt, !time.isFinite || time <= 0 { throw SnapshotError.invalidResponse }
        return WorkspaceSnapshot(workspaceKey: key, workspaceName: p.workspaceName ?? "개인 워크스페이스", balance: CreditBalance(total: total, reserved: reserved, available: available), jobs: jobs, fetchedAt: now, historyTruncated: p.historyTruncated ?? false, concurrency: p.concurrency, balanceFetchedAt: p.balanceFetchedAt.map { Date(timeIntervalSince1970: $0 / 1000) }, balanceIsStale: p.balanceIsStale ?? false)
    }
}
