// 기능 분류: 지크에 밀착한 원형 메뉴와 상단 고정 현황 배치
import Foundation

public struct PetQuickMenuLayout {
    public static let preferredButtonSize = CGSize(width: 48, height: 48)
    public static let summarySize = CGSize(width: 232, height: 104)
    public let protectedFrame: CGRect
    public let protectedFrames: [CGRect]
    public let summary: CGRect
    public let buttons: [CGRect]
    public let radius: CGFloat
    public let usesFallbackGrid: Bool

    /// 화면 좌표(위가 +Y)를 사용한다. 홈 네 항목은 아래쪽 원호의 좌우 대칭 위치,
    /// 하위 도구는 같은 반지름의 넓은 원호에 배치한다.
    public init(anchor: CGRect, screen: CGRect, count: Int, home: Bool, labelWidth: CGFloat = 110) {
        let bounds = screen.insetBy(dx: 8, dy: 8)
        // 지크 PNG의 불투명 영역(가로 약 43%, 세로 약 93%)에 맞춰 투명 여백을 제외한다.
        let body = anchor.insetBy(dx: anchor.width * 0.28, dy: anchor.height * 0.04)
        protectedFrame = body
        protectedFrames = [body]
        summary = CGRect(
            x: anchor.midX - Self.summarySize.width / 2,
            y: anchor.maxY + 8,
            width: Self.summarySize.width,
            height: Self.summarySize.height
        )

        let size: CGSize
        if !home && count >= 7 {
            size = CGSize(width: 40, height: 40)
        } else if !home && count >= 6 {
            size = CGSize(width: 44, height: 44)
        } else {
            size = CGSize(width: 48, height: 48)
        }
        let protectedSnapshot = protectedFrame
        let summarySnapshot = summary
        // 홈 네 항목은 지크와 살짝 여유를 두고, 하위 메뉴는 최대한 밀착한다.
        var chosenRadius = home ? max(82, anchor.width / 2 + size.width / 2 + 18) : max(64, anchor.width / 2 + size.width / 2 + 6)
        var radialFrames: [CGRect] = []
        while chosenRadius <= 180 {
            // 위쪽 끝 버튼이 현황 박스 아래에 머무르도록 반지름마다 원호 범위를 다시 계산한다.
            let headroom = summarySnapshot.minY - 4 - size.height / 2 - anchor.midY
            let liftLimit = asin(min(1, max(-1, headroom / chosenRadius))) * 180 / .pi
            let angles = Self.angles(count: count, home: home, maxLift: liftLimit)
            radialFrames = angles.map { Self.frame(anchor: anchor, radius: chosenRadius, angle: $0, size: size) }
            let clearsProtected = radialFrames.allSatisfy { !$0.intersects(protectedSnapshot) && !$0.intersects(summarySnapshot) }
            let clearsButtons = radialFrames.indices.allSatisfy { index in
                !radialFrames.dropFirst(index + 1).contains { radialFrames[index].intersects($0) }
            }
            if clearsProtected && clearsButtons { break }
            chosenRadius += 1
        }
        radius = chosenRadius

        if radialFrames.count == count && radialFrames.allSatisfy(bounds.contains) {
            usesFallbackGrid = false
            buttons = radialFrames
        } else {
            usesFallbackGrid = true
            buttons = Self.fallbackButtons(
                anchor: anchor,
                protected: protectedFrame,
                bounds: bounds,
                count: count,
                size: size
            )
        }
    }

    private static func angles(count: Int, home: Bool, maxLift: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [270] }
        if home && count == 4 { return [180, 225, 315, 0] }
        // 항목 수에 맞춘 좌우 대칭 원호. 위로 올라가는 각도는 현황 박스와 겹치지 않는 만큼만 쓴다.
        let preferredLift: CGFloat
        switch count {
        case 5: preferredLift = -5
        case 6: preferredLift = 20
        default: preferredLift = 32.5
        }
        let lift = min(preferredLift, maxLift)
        let start = 180 - lift
        let end = 360 + lift
        return (0..<count).map { start + CGFloat($0) * (end - start) / CGFloat(count - 1) }
    }

    private static func frame(anchor: CGRect, radius: CGFloat, angle: CGFloat, size: CGSize) -> CGRect {
        let radians = angle * .pi / 180
        return CGRect(
            x: anchor.midX + cos(radians) * radius - size.width / 2,
            y: anchor.midY + sin(radians) * radius - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// 화면 가장자리에서 원이 잘리는 경우 현황 박스 아래의 빈 쪽에 작은 격자로 접는다.
    private static func fallbackButtons(
        anchor: CGRect,
        protected: CGRect,
        bounds: CGRect,
        count: Int,
        size: CGSize
    ) -> [CGRect] {
        let gap: CGFloat = 8
        let rightSpace = bounds.maxX - protected.maxX - 12
        let leftSpace = protected.minX - bounds.minX - 12
        let placeRight = rightSpace >= leftSpace
        let available = max(0, placeRight ? rightSpace : leftSpace)
        let columns = available >= size.width * 2 + gap ? 2 : 1
        let rows = Int(ceil(Double(count) / Double(columns)))
        let totalHeight = CGFloat(rows) * size.height + CGFloat(max(0, rows - 1)) * gap
        let top = min(max(anchor.maxY - gap, bounds.minY + totalHeight), bounds.maxY)
        let startX = placeRight
            ? protected.maxX + 12
            : protected.minX - 12 - CGFloat(columns) * size.width - CGFloat(columns - 1) * gap
        return (0..<count).map { index in
            let column = index / rows
            let row = index % rows
            return CGRect(
                x: min(max(startX + CGFloat(column) * (size.width + gap), bounds.minX), bounds.maxX - size.width),
                y: top - CGFloat(row + 1) * size.height - CGFloat(row) * gap,
                width: size.width,
                height: size.height
            )
        }
    }
}
