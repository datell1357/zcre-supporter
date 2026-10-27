// 기능 분류: 중앙 지크와 작업 문구를 침범하지 않는 메뉴 배치
import Foundation

public struct PetQuickMenuLayout {
    public static let buttonSize: CGFloat = 56
    public let protectedFrame: CGRect
    public let protectedFrames: [CGRect]
    public let summary: CGRect
    public let buttons: [CGRect]
    public let radius: CGFloat

    /// 화면 좌표(위가 +Y)를 사용한다. 화면 끝에서는 지크를 움직이지 않고 버튼만 빈 공간으로 옮긴다.
    public init(anchor: CGRect, screen: CGRect, count: Int, home: Bool, labelWidth: CGFloat = 110) {
        let bounds = screen.insetBy(dx: 8, dy: 8)
        // 작업 문구의 폭을 지크 전체 높이에 적용하면 양옆에 불필요한 빈 공간이 생긴다.
        // 몸과 아래 문구를 각각 보호하고, 실제 충돌 없는 가장 작은 원을 찾는다.
        let body = anchor.insetBy(dx: -4, dy: -4)
        let label = CGRect(x: anchor.midX - labelWidth / 2, y: anchor.minY - 30,
                           width: labelWidth, height: 24)
        let protected = body.union(label)
        protectedFrame = protected
        protectedFrames = [body, label]
        let uniformHome = home && count == 5
        let edge = Self.buttonSize, spacing: CGFloat = 6
        func box(_ angle: CGFloat, _ distance: CGFloat) -> CGRect {
            let a = angle * .pi / 180
            return CGRect(x: anchor.midX + cos(a) * distance - edge / 2,
                          y: anchor.midY + sin(a) * distance - edge / 2, width: edge, height: edge)
        }
        let angles: [CGFloat] = home ? (uniformHome ? [150, 30, 330, 210, 270] : [180, 0, 270]) : (0..<count).map { 135 + CGFloat($0) * 270 / CGFloat(max(1, count - 1)) }
        var compactRadius = max(80, anchor.width / 2 + edge / 2 + spacing)
        while true {
            let frames = angles.map { box($0, compactRadius) }
            let clearsPet = frames.allSatisfy { frame in
                ![body, label].contains { $0.insetBy(dx: -2, dy: -2).intersects(frame) }
            }
            let clearsButtons = frames.indices.allSatisfy { index in
                !frames.dropFirst(index + 1).contains { frames[index].insetBy(dx: -spacing / 2, dy: -spacing / 2).intersects($0) }
            }
            if clearsPet && clearsButtons { break }
            compactRadius += 2
        }
        radius = compactRadius
        let r = compactRadius
        let wanted = angles.map { box($0, r) }
        let top = max(anchor.maxY + 10, (wanted.map(\.maxY).max() ?? anchor.maxY) + 12)
        let summarySize = CGSize(width: 232, height: 104)
        func bounded(_ rect: CGRect) -> CGRect {
            CGRect(x: min(max(rect.minX, bounds.minX), bounds.maxX - rect.width),
                   y: min(max(rect.minY, bounds.minY), bounds.maxY - rect.height), width: rect.width, height: rect.height)
        }
        let candidates = [
            CGRect(x: anchor.midX - 116, y: top, width: 232, height: 104),
            CGRect(x: anchor.midX - 116, y: protected.minY - 120, width: 232, height: 104),
            CGRect(x: protected.maxX + 16, y: anchor.midY - 52, width: 232, height: 104),
            CGRect(x: protected.minX - 248, y: anchor.midY - 52, width: 232, height: 104)
        ].map(bounded)
        let summaryFrame = candidates.first { bounds.contains($0) && !$0.intersects(protected) }
            ?? CGRect(origin: bounds.origin, size: summarySize)
        summary = summaryFrame
        var occupied = [body, label, summaryFrame.insetBy(dx: -spacing, dy: -spacing)]
        var placed: [CGRect] = []
        for preferred in wanted {
            var candidates = [preferred]
            for distance in [r, r + 90, r + 180, r + 270] {
                candidates += stride(from: CGFloat(0), to: 360, by: 15).map { box($0, distance) }
                    .sorted { hypot($0.midX - preferred.midX, $0.midY - preferred.midY) < hypot($1.midX - preferred.midX, $1.midY - preferred.midY) }
            }
            // 작은 화면·모서리에서도 버튼끼리 겹치지 않도록 화면 내부의 빈 격자로 마지막 보정한다.
            for y in stride(from: bounds.minY, through: bounds.maxY - edge, by: edge + spacing) {
                for x in stride(from: bounds.minX, through: bounds.maxX - edge, by: edge + spacing) {
                    candidates.append(CGRect(x: x, y: y, width: edge, height: edge))
                }
            }
            if let frame = candidates.first(where: { rect in bounds.contains(rect) && !occupied.contains { $0.intersects(rect) } }) {
                placed.append(frame); occupied.append(frame.insetBy(dx: -spacing, dy: -spacing))
            }
        }
        buttons = placed
    }
}
