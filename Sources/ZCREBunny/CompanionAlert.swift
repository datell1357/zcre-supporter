// 기능 분류: 완료·실패·잔액 부족 알림의 로컬 표시 모델
import Foundation

/// 계정별 로컬 알림 모델이며 프롬프트·토큰·결과 URL을 저장하지 않는다.
struct CompanionAlert: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case completed, failed, lowCredits
        var symbol: String {
            switch self {
            case .completed: "checkmark.circle.fill"
            case .failed: "exclamationmark.circle.fill"
            case .lowCredits: "bolt.circle.fill"
            }
        }
        var path: String { self == .lowCredits ? "/credits" : "/history" }
    }
    enum Source: String, Codable { case notification, workHistory }
    var id = UUID()
    let kind: Kind
    let title: String
    let body: String
    var createdAt = Date.now
    var isRead = false
    var source: Source = .notification
    var jobKey: String?
}
