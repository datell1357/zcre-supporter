// 기능 분류: 화면 좌표 · 목덜이 고정 · 8방향 산책과 이동 테스트
import Foundation
import CoreGraphics

public enum PetWorkFacing {
    /// 지크가 속한 화면의 오른쪽에서는 왼쪽을, 왼쪽에서는 오른쪽을 바라본다.
    public static func mirrored(rabbit: CGRect, screen: CGRect) -> Bool { rabbit.midX > screen.midX }
}

/// 지크 창이 움직여도 화면 좌표의 기준은 변하지 않는다.
public struct PetDragAnchor: Sendable {
    public let windowOrigin: CGPoint
    public let pointerOrigin: CGPoint
    /// 드래그 시작 시 창과 마우스의 화면 좌표를 기록한다.
    public init(windowOrigin: CGPoint, pointerOrigin: CGPoint) {
        self.windowOrigin = windowOrigin; self.pointerOrigin = pointerOrigin
    }
    /// 시작점으로부터 마우스가 이동한 거리만 창 위치에 더한다.
    public func origin(for pointer: CGPoint) -> CGPoint {
        CGPoint(x: windowOrigin.x + pointer.x - pointerOrigin.x,
                y: windowOrigin.y + pointer.y - pointerOrigin.y)
    }
    /// 현재 마우스 좌표에서 목덜이 기준점 오프셋을 빼서 창 위치를 결정한다.
    public static func origin(pointer: CGPoint, grabPoint: CGPoint) -> CGPoint {
        CGPoint(x: pointer.x - grabPoint.x, y: pointer.y - grabPoint.y)
    }
}

/// 붙잡힌 자세는 마지막으로 충분히 움직인 수평 방향을 바라본다.
public struct PetDragFacing: Sendable {
    public private(set) var mirrored: Bool
    private var turningPointX: CGFloat
    /// 드래그 좌우 방향 판별의 기준 위치와 현재 방향을 저장한다.
    public init(pointerX: CGFloat, mirrored: Bool) {
        turningPointX = pointerX; self.mirrored = mirrored
    }
    /// 작은 마우스 떨림에는 방향을 유지하고 충분히 반대로 이동했을 때만 좌우를 뒤집는다.
    public mutating func update(pointerX: CGFloat) {
        turningPointX = mirrored ? min(turningPointX, pointerX) : max(turningPointX, pointerX)
        let reversedDistance = mirrored ? pointerX - turningPointX : turningPointX - pointerX
        if reversedDistance >= 8 {
            mirrored.toggle()
            turningPointX = pointerX
        }
    }
}

/// 캐릭터만 확대·축소하며 글자와 클릭 영역은 읽기 쉬운 크기를 유지한다.
public struct PetLayout: Sendable {
    public let rabbitSize: CGSize
    public let panelSize: CGSize
    public let rabbitFrame: CGRect
    public let bubbleFrame: CGRect
    public var scruffPoint: CGPoint { CGPoint(x: rabbitFrame.midX, y: rabbitFrame.midY) }
    /// 지크 크기를 제한 범위로 보정하고 읽을 수 있는 고정 크기 말풍선·입력 영역을 계산한다.
    public init(scale: Double) {
        let scale = min(1.5, max(0.7, scale))
        rabbitSize = CGSize(width: 128 * 0.7 * scale, height: 155 * 0.7 * scale)
        panelSize = CGSize(width: 280, height: 128 + rabbitSize.height)
        rabbitFrame = CGRect(x: (280 - rabbitSize.width) / 2, y: 36, width: rabbitSize.width, height: rabbitSize.height)
        bubbleFrame = CGRect(x: 14, y: 44 + rabbitSize.height, width: 252, height: 76)
    }
}

public enum WalkDirection: Int, CaseIterable, Sendable {
    case east, northEast, north, northWest, west, southWest, south, southEast
    public var vector: CGPoint {
        let angle = Double(rawValue) * .pi / 4
        return CGPoint(x: cos(angle), y: sin(angle))
    }
    public var mirrored: Bool { self == .west || self == .northWest || self == .southWest }
    /// 이동 벡터를 가장 가까운 8방향 중 하나로 변환한다.
    public static func toward(_ delta: CGPoint) -> WalkDirection {
        let sector = Int((atan2(delta.y, delta.x) / (.pi / 4)).rounded())
        return WalkDirection(rawValue: (sector + 8) % 8)!
    }
}

public enum PetRoaming {
    /// 화면 가장자리의 제약이 없으면 8방향 모두 동일한 선택 기회를 갖는다.
    /// 8방향을 무작위로 시도해 허용된 영역 안의 산책 목표를 선택한다.
    public static func destination<R: RandomNumberGenerator>(from origin: CGPoint, in bounds: CGRect, using random: inout R) -> CGPoint? {
        for direction in WalkDirection.allCases.shuffled(using: &random) {
            let v = direction.vector
            let availableX = abs(v.x) < 0.001 ? CGFloat.infinity : (v.x > 0 ? bounds.maxX - origin.x : bounds.minX - origin.x) / v.x
            let availableY = abs(v.y) < 0.001 ? CGFloat.infinity : (v.y > 0 ? bounds.maxY - origin.y : bounds.minY - origin.y) / v.y
            let maximum = min(210, availableX, availableY)
            guard maximum >= 40 else { continue }
            let distance = CGFloat.random(in: 40...maximum, using: &random)
            let target = CGPoint(x: origin.x + v.x * distance, y: origin.y + v.y * distance)
            if bounds.insetBy(dx: -0.01, dy: -0.01).contains(target) { return target }
        }
        // 수동 배치는 제한하지 않으며 화면 밖 지크는 산책으로 안쪽에 돌아올 수 있다.
        return bounds.contains(origin) ? nil : CGPoint(x: bounds.midX, y: bounds.midY)
    }
    /// 목표를 지나치지 않도록 이동 거리를 제한하며 대각선에서도 같은 속도를 유지한다.
    public static func step(from origin: CGPoint, toward target: CGPoint, distance: CGFloat) -> CGPoint {
        let dx = target.x - origin.x, dy = target.y - origin.y
        let length = hypot(dx, dy)
        guard length > distance, length > 0 else { return target }
        return CGPoint(x: origin.x + dx / length * distance, y: origin.y + dy / length * distance)
    }
}

/// 타이머 호출이 늦어져도 경과 시간에 따라 2초 동안 60포인트를 이동한다.
public struct PetMovementTest: Sendable {
    public static let duration: TimeInterval = 2
    public let origin: CGPoint
    public let direction: WalkDirection
    /// 방향 테스트의 출발점과 방향을 기록한다.
    public init(origin: CGPoint, direction: WalkDirection) {
        self.origin = origin; self.direction = direction
    }
    /// 경과 시간을 2초로 제한해 초당 30포인트 속도의 테스트 위치를 반환한다.
    public func position(elapsed: TimeInterval) -> CGPoint {
        let distance = min(Self.duration, max(0, elapsed)) * 30
        let vector = direction.vector
        return CGPoint(x: origin.x + vector.x * distance, y: origin.y + vector.y * distance)
    }
}
