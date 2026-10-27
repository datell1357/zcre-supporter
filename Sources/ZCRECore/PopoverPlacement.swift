// 기능 분류: 지크 주변 현황판의 화면 내 자동 배치
import CoreGraphics

/// 보조 모니터를 포함해 모든 배치는 위쪽이 양수인 화면 좌표를 사용한다.
public struct PopoverPlacement: Sendable {
    public enum Side: Sendable { case above, below, right, left }
    public let side: Side
    public let contentSize: CGSize

    /// 위·아래·옆의 가용 공간을 비교하고 화면 안에 들어가는 위치와 크기를 선택한다.
    public init(anchor: CGRect, visibleFrame: CGRect, preferredSize: CGSize) {
        // 팝오버 테두리·화살표·화면 가장자리 여유 공간을 확보한다.
        let bounds = visibleFrame.insetBy(dx: 16, dy: 16)
        contentSize = CGSize(width: min(preferredSize.width, max(1, bounds.width)),
                             height: min(preferredSize.height, max(1, bounds.height)))
        let gap: CGFloat = 16
        let candidates: [(Side, CGFloat)] = [
            (.above, (bounds.maxY - anchor.maxY - gap) / contentSize.height),
            (.below, (anchor.minY - bounds.minY - gap) / contentSize.height),
            (.right, (bounds.maxX - anchor.maxX - gap) / contentSize.width),
            (.left, (anchor.minX - bounds.minX - gap) / contentSize.width)
        ]
        // 세로 카드가 온전히 들어가면 우선 선택한다. 화면 중앙에서는
        // 옆 배치가 지크와 카드 모두를 보이게 하는 데 유리하다.
        if let fitting = candidates.first(where: { $0.1 >= 1 }) {
            side = fitting.0
        } else {
            side = candidates.max(by: { $0.1 < $1.1 })!.0
        }
    }
}
