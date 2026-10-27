// 기능 분류: 공개 서비스 상태 응답 검증과 오래된 집계 판정
import Foundation

public enum ServiceHealth: String, Decodable, Sendable, CaseIterable {
    case operational, delayed, degraded, checking

    /// 알려진 서비스 상태만 매핑하고 새 상태 값은 확인 중으로 취급한다.
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .checking
    }
    public var label: String {
        switch self {
        case .operational: "정상"
        case .delayed: "지연"
        case .degraded: "오류 증가"
        case .checking: "확인 중"
        }
    }
}

public struct ServiceStatusSnapshot: Decodable, Equatable, Sendable {
    public let calculatedAt: Date?
    public let stale: Bool
    public let window: String
    public let granularity: String
    public let measurement: String
    public let models: [Model]

    public struct Model: Decodable, Equatable, Identifiable, Sendable {
        public let modelName: String
        public let label: String
        public let state: ServiceHealth
        public let series: [Series]
        public var id: String { modelName }
        public var health: ServiceHealth {
            // 공개 페이지처럼 평가된 데이터 지점이 하나 이상 있어야 정상으로 표시한다.
            state == .operational && !series.contains(where: { $0.hasData }) ? .checking : state
        }
    }
    public struct Series: Decodable, Equatable, Sendable {
        public let variant: String
        public let state: ServiceHealth
        public let points: [Point]
        public var hasData: Bool { points.contains { $0.state == "available" } }
        public var health: ServiceHealth { state == .operational && !hasData ? .checking : state }
        public var label: String {
            switch variant { case "standard": "일반"; case "draft": "드래프트"; case "final": "본생성"; default: variant }
        }
    }
    public struct Point: Decodable, Equatable, Sendable { public let state: String }

    /// 서버 기준 시각과 집계 시각이 5분 이상 차이 나거나 서버가 오래되었다고 표시하면 유효하지 않게 본다.
    public func isStale(serverNow: Date) -> Bool {
        guard let calculatedAt, !stale else { return true }
        return abs(serverNow.timeIntervalSince(calculatedAt)) > 300
    }

    /// 집계 범위·측정 방식·모델 중복·배열 크기·시각을 검증하여 공개 상태 모델을 만든다.
    public static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid status timestamp"))
        }
        let result = try decoder.decode(Self.self, from: data)
        guard result.window == "24h", result.granularity == "1h", result.measurement == "request_created_to_completed",
              !result.models.isEmpty, result.models.count <= 50,
              Set(result.models.map(\.id)).count == result.models.count,
              result.models.allSatisfy({
                  !$0.id.isEmpty && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.label.count <= 60 &&
                  $0.series.count <= 3 && $0.series.allSatisfy { $0.points.count <= 200 }
              }) else { throw SnapshotError.invalidResponse }
        return result
    }
}
