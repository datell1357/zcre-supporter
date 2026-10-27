// 검증 분류: 로컬 데이터와 번들 리소스 기반 회귀 테스트. 실제 생성·결제 요청은 보내지 않는다.
import Foundation
import CoreGraphics
import Testing
@testable import ZCRECore

// 창이 움직여도 드래그 계산에 좌표 피드백이 생기지 않는지 검증한다.
@Test func dragUsesScreenDisplacementWithoutWindowFeedback() {
    let anchor = PetDragAnchor(windowOrigin: CGPoint(x: 400, y: 200), pointerOrigin: CGPoint(x: 445, y: 270))
    let pointer = CGPoint(x: 545, y: 310)
    #expect(anchor.origin(for: pointer) == CGPoint(x: 500, y: 240))
    // Repeated events after moving the window must not move it again.
    #expect(anchor.origin(for: CGPoint(x: 555, y: 315)) == CGPoint(x: 510, y: 245))
    #expect(anchor.origin(for: CGPoint(x: 445, y: 270)) == anchor.windowOrigin)
}

// 주 화면 왼쪽·아래의 음수 좌표에서도 드래그가 작동하는지 검증한다.
@Test func dragWorksAcrossNegativeScreenCoordinates() {
    let anchor = PetDragAnchor(windowOrigin: CGPoint(x: 20, y: -500), pointerOrigin: CGPoint(x: 60, y: -450))
    #expect(anchor.origin(for: CGPoint(x: -200, y: -700)) == CGPoint(x: -240, y: -750))
}

// 작은 포인터 떨림에는 방향을 유지하고 큰 이동에는 좌우를 전환하는지 검증한다.
@Test func heldPoseTurnsBothWaysWithoutFlickeringFromPointerJitter() {
    var facing = PetDragFacing(pointerX: 100, mirrored: false)
    for x in [99.0, 101, 98, 100, 96, 95] {
        facing.update(pointerX: x)
        #expect(!facing.mirrored)
    }
    facing.update(pointerX: 93)
    #expect(facing.mirrored)
    // Slow movement still accumulates; horizontal reversals must pass 8 points.
    for x in [90.0, 85, 80, 82, 85, 87] {
        facing.update(pointerX: x)
        #expect(facing.mirrored)
    }
    facing.update(pointerX: 88)
    #expect(!facing.mirrored)
    for _ in 0..<20 { facing.update(pointerX: 88) }
    #expect(!facing.mirrored)
    var initiallyLeft = PetDragFacing(pointerX: -500, mirrored: true)
    initiallyLeft.update(pointerX: -490)
    #expect(!initiallyLeft.mirrored)
}

// 새 100% 기본 크기가 이전 70% 캐릭터 높이와 같은지 검증한다.
@Test func newDefaultMatchesFormerSeventyPercentCharacter() {
    let layout = PetLayout(scale: 1)
    #expect(abs(layout.rabbitSize.width - 89.6) < 0.001)
    #expect(abs(layout.rabbitSize.height - 108.5) < 0.001)
}

// 지크 크기를 줄여도 말풍선 글 영역이 줄지 않는지 검증한다.
@Test func speechAreaDoesNotShrinkWithCharacter() {
    let small = PetLayout(scale: 0.7), large = PetLayout(scale: 1.5)
    #expect(small.bubbleFrame.size == large.bubbleFrame.size)
    #expect(small.panelSize.width == large.panelSize.width)
    #expect(small.rabbitFrame.minY == large.rabbitFrame.minY)
    #expect(small.rabbitFrame.maxY < small.bubbleFrame.minY)
    #expect(large.bubbleFrame.maxY <= large.panelSize.height)
}

// 모든 배율에서 목덜이가 마우스 끝에 고정되는지 검증한다.
@Test func grabbedScruffStaysAtPointerAtEveryScaleWithoutFeedback() {
    for scale in [0.7, 1, 1.5] {
        let layout = PetLayout(scale: scale)
        for pointer in [CGPoint(x: -800, y: 0), CGPoint(x: 300, y: 1500)] {
            let origin = PetDragAnchor.origin(pointer: pointer, grabPoint: layout.scruffPoint)
            #expect(abs(origin.x + layout.scruffPoint.x - pointer.x) < 0.001)
            #expect(abs(origin.y + layout.scruffPoint.y - pointer.y) < 0.001)
            #expect(PetDragAnchor.origin(pointer: pointer, grabPoint: layout.scruffPoint) == origin)
        }
    }
}

private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64 = 12345
    // 재현 가능한 산책 방향 테스트를 위한 의사 난수를 만든다.
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// 산책이 8방향을 모두 선택하고 대각선 속도도 일정한지 검증한다.
@Test func roamingCanChooseAllEightDirectionsAndKeepsDiagonalSpeedEqual() {
    var random = SeededRandom()
    let origin = CGPoint(x: 500, y: 400), bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    var seen = Set<Int>()
    for _ in 0..<400 {
        let target = PetRoaming.destination(from: origin, in: bounds, using: &random)!
        #expect(bounds.contains(target))
        seen.insert(WalkDirection.toward(CGPoint(x: target.x-origin.x, y: target.y-origin.y)).rawValue)
        let next = PetRoaming.step(from: origin, toward: target, distance: 1.5)
        #expect(abs(hypot(next.x-origin.x, next.y-origin.y)-1.5) < 0.001)
    }
    #expect(seen.count == 8)
}

// 가장자리에서 유효한 안쪽 경로를 찾고 목표를 지나치지 않는지 검증한다.
@Test func roamingFromEdgesFindsAnInwardPathAndNeverOvershoots() {
    var random = SeededRandom()
    let bounds = CGRect(x: -1600, y: -300, width: 1500, height: 900)
    for point in [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.maxY)] {
        let target = PetRoaming.destination(from: point, in: bounds, using: &random)!
        #expect(bounds.insetBy(dx: -0.01, dy: -0.01).contains(target))
    }
    #expect(PetRoaming.step(from: .zero, toward: CGPoint(x: 0.5, y: 0.5), distance: 1.5) == CGPoint(x: 0.5, y: 0.5))
}

// 모든 이동 테스트가 동일 속도로 정확히 2초 동안 움직이는지 검증한다.
@Test func movementTestsRunEveryDirectionForTwoSecondsAtTheSameSpeed() {
    let origin = CGPoint(x: -400, y: 700)
    for direction in WalkDirection.allCases {
        let test = PetMovementTest(origin: origin, direction: direction)
        #expect(test.position(elapsed: -1) == origin)
        for elapsed in [0.5, 1, 1.8, 2, 2.15, 20] {
            let point = test.position(elapsed: elapsed)
            let expected = min(elapsed, 2)*30
            #expect(abs(hypot(point.x-origin.x, point.y-origin.y)-expected) < 0.001)
            #expect(WalkDirection.toward(CGPoint(x: point.x-origin.x, y: point.y-origin.y)) == direction)
        }
        #expect(test.position(elapsed: 2) == test.position(elapsed: 10))
    }
}
