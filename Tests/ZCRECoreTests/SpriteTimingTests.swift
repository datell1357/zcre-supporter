// 검증 분류: 로컬 데이터와 번들 리소스 기반 회귀 테스트. 실제 생성·결제 요청은 보내지 않는다.
import Testing
@testable import ZCRECore

// 모션 고유 프레임 간격에 따라 반복하는지 검증한다.
@Test func spriteLoopsUseNativeFrameDelay() {
    #expect(SpriteTiming.frame(elapsed: 0.24, count: 8, delayMilliseconds: 100, loop: true) == 2)
    #expect(SpriteTiming.frame(elapsed: 0.84, count: 8, delayMilliseconds: 100, loop: true) == 0)
    #expect(SpriteTiming.frame(elapsed: -1, count: 8, delayMilliseconds: 100, loop: true) == 0)
}

// 단발 모션이 반복되지 않고 잘못된 시간이 안전하게 처리되는지 검증한다.
@Test func completionDoesNotWrapAndInvalidTimingIsSafe() {
    #expect(SpriteTiming.frame(elapsed: 2, count: 8, delayMilliseconds: 100, loop: false) == 7)
    #expect(SpriteTiming.frame(elapsed: .infinity, count: 8, delayMilliseconds: 100, loop: true) == 0)
    #expect(SpriteTiming.frame(elapsed: 2, count: 0, delayMilliseconds: 0, loop: true) == 0)
}
