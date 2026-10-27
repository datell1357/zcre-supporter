// 검증 분류: 로컬 데이터와 번들 리소스 기반 회귀 테스트. 실제 생성·결제 요청은 보내지 않는다.
import CoreGraphics
import Testing
@testable import ZCRECore

private let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
private let card = CGSize(width: 370, height: 620)

// 지크가 화면 위·아래에 있을 때 반대쪽 여유 공간으로 현황판을 여는지 검증한다.
@Test func bottomRabbitOpensCardAboveAndTopRabbitBelow() {
    #expect(PopoverPlacement(anchor: CGRect(x: 650, y: 40, width: 90, height: 110), visibleFrame: display, preferredSize: card).side == .above)
    #expect(PopoverPlacement(anchor: CGRect(x: 650, y: 750, width: 90, height: 110), visibleFrame: display, preferredSize: card).side == .below)
}

// 높은 현황판이 잘리지 않도록 옆 공간을 선택하는지 검증한다.
@Test func middleRabbitUsesAvailableSideInsteadOfClippingTallCard() {
    #expect(PopoverPlacement(anchor: CGRect(x: 30, y: 400, width: 90, height: 110), visibleFrame: display, preferredSize: card).side == .right)
    #expect(PopoverPlacement(anchor: CGRect(x: 1320, y: 400, width: 90, height: 110), visibleFrame: display, preferredSize: card).side == .left)
}

// 다중 모니터와 음수 좌표에서 지크가 있는 화면을 기준으로 배치하는지 검증한다.
@Test func placementUsesTheRabbitsDisplayIncludingNegativeCoordinates() {
    let secondary = CGRect(x: -1440, y: -900, width: 1440, height: 900)
    #expect(PopoverPlacement(anchor: CGRect(x: -130, y: -500, width: 90, height: 110), visibleFrame: secondary, preferredSize: card).side == .left)
    #expect(PopoverPlacement(anchor: CGRect(x: -740, y: -850, width: 90, height: 110), visibleFrame: secondary, preferredSize: card).side == .above)
}

// 높이가 작은 화면에서 현황판 크기를 제한하는지 검증한다.
@Test func shortScreenKeepsCardWithinUsableHeight() {
    let placement = PopoverPlacement(anchor: CGRect(x: 1200, y: 200, width: 90, height: 110), visibleFrame: CGRect(x: 0, y: 40, width: 1280, height: 560), preferredSize: card)
    #expect(placement.contentSize == CGSize(width: 370, height: 528))
    #expect(placement.side == .left)
}

// 공간이 부족하면 가장 넓은 쪽을 선택하는지 검증한다.
@Test func crampedScreenChoosesSideWithMostUsableSpace() {
    let placement = PopoverPlacement(anchor: CGRect(x: 350, y: 200, width: 90, height: 110), visibleFrame: CGRect(x: 0, y: 0, width: 600, height: 500), preferredSize: card)
    #expect(placement.side == .left)
}
