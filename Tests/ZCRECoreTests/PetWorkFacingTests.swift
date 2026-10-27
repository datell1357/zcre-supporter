// 검증 분류: 화면 중심 기준 작업 자세. 음수 좌표의 보조 화면도 독립적으로 판단한다.
import CoreGraphics
import Testing
@testable import ZCRECore

@Test func workingFacesTheMiddleOfItsOwnDisplay() {
    for origin in [CGPoint.zero, CGPoint(x: -1920, y: 200), CGPoint(x: 1920, y: -1080)] {
        let screen = CGRect(origin: origin, size: CGSize(width: 1920, height: 1080))
        let left = CGRect(x: origin.x + 200, y: origin.y + 200, width: 100, height: 150)
        let right = CGRect(x: origin.x + 1600, y: origin.y + 200, width: 100, height: 150)
        #expect(!PetWorkFacing.mirrored(rabbit: left, screen: screen))
        #expect(PetWorkFacing.mirrored(rabbit: right, screen: screen))
    }
}
