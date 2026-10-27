// 기능 분류: 디버그 모션 종류 · 방향 · 재생 시간 정의
import ZCRECore

enum PetActionTest: Int, CaseIterable {
    case idle, dragLeft, dragRight
    case up, down, left, right, upLeft, upRight, downLeft, downRight
    case working, complete, failed, wave

    var previewDuration: Double { self == .working ? 6 : PetMovementTest.duration }

    var direction: WalkDirection? {
        switch self {
        case .up: .north
        case .down: .south
        case .left: .west
        case .right: .east
        case .upLeft: .northWest
        case .upRight: .northEast
        case .downLeft: .southWest
        case .downRight: .southEast
        default: nil
        }
    }
    var motion: ZicMotion {
        if let direction { return .walking(direction) }
        switch self {
        case .dragLeft, .dragRight: return .drag
        case .complete: return .complete
        case .working: return .working
        case .failed: return .cry
        case .wave: return .wave
        default: return .idle
        }
    }
    var title: String {
        switch self {
        case .idle: "대기 · 2초"
        case .dragLeft: "잡힘 · 왼쪽 · 2초"
        case .dragRight: "잡힘 · 오른쪽 · 2초"
        case .up: "↑ 위로 이동 · 2초"
        case .down: "↓ 아래로 이동 · 2초"
        case .left: "← 왼쪽으로 이동 · 2초"
        case .right: "→ 오른쪽으로 이동 · 2초"
        case .upLeft: "↖ 왼쪽 위로 이동 · 2초"
        case .upRight: "↗ 오른쪽 위로 이동 · 2초"
        case .downLeft: "↙ 왼쪽 아래로 이동 · 2초"
        case .downRight: "↘ 오른쪽 아래로 이동 · 2초"
        case .complete: "작업 완료 · 한 번 재생"
        case .working: "작업 중 · 6초"
        case .failed: "작업 실패 · 한 번 재생"
        case .wave: "손 흔들기 · 한 번 재생"
        }
    }
}
