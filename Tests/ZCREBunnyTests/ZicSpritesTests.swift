// 검증 분류: 로컬 데이터와 번들 리소스 기반 회귀 테스트. 실제 생성·결제 요청은 보내지 않는다.
import AppKit
import Testing
import ZCRECore
@testable import ZCREBunny

// 번들 모션의 시간·프레임·기준점이 유효하게 해석되는지 검증한다.
@Test @MainActor func bundledZicMotionsDecodeWithTheirNativeTimingAndAnchors() {
    let sprites = ZicSprites.shared
    for state in ZicMotion.allCases {
        #expect(sprites.hasAnimation(state), "Missing motion resource: \(state.rawValue)")
        let clip = sprites.clip(state)
        #expect(clip.frames.count == clip.metadata.frames)
        #expect(clip.duration > 0.25 && clip.duration < 10)
        #expect(clip.metadata.body_h == 384)
        #expect(clip.metadata.loop == (state != .complete && state != .cry && state != .wave))
        #expect(clip.anchor.x.isFinite && clip.anchor.y.isFinite)
        #expect(clip.anchor.x >= 0 && clip.anchor.x <= Double(clip.metadata.w))
        #expect(clip.anchor.y >= 0 && clip.anchor.y <= Double(clip.metadata.h))
        if state == .drag {
            #expect(clip.metadata.grab_anchor?.count == 2)
            #expect(clip.grabAnchor.x > 0 && clip.grabAnchor.x < clip.anchor.x)
            #expect(clip.grabAnchor.y > 0 && clip.grabAnchor.y < Double(clip.metadata.h))
        }
        let poses = clip.frames.compactMap(\.tiffRepresentation)
        #expect(Set(poses).count > 1, "Motion must contain changing poses: \(state.rawValue)")
    }
}

// 완료 모션은 한 번 재생하고 동작 줄이기는 정지 자세를 사용하는지 검증한다.
@Test @MainActor func completedMotionStopsAndReducedMotionUsesOnePose() {
    let clip = ZicSprites.shared.clip(.complete)
    #expect(clip.frame(elapsed: clip.duration + 1, animate: true) === clip.frames.last)
    #expect(clip.frame(elapsed: clip.duration / 2, animate: false) === clip.frames.first)
}

// 작업 모션 반복과 지원 크기별 창 영역 수용 여부를 검증한다.
@Test @MainActor func workingLoopsWrapAndFitThePetWindowAtEverySupportedSize() {
    let sprites = ZicSprites.shared
    for state in [ZicMotion.working, .run] {
        let clip = sprites.clip(state)
        #expect(clip.frame(elapsed: clip.duration + 0.001, animate: true) === clip.frames.first)
        #expect(clip.frame(elapsed: clip.duration / 2, animate: false) === clip.frames.first)
    }
    let clip = sprites.clip(.working)
    for percent in stride(from: 70, through: 150, by: 5) {
        let layout = PetLayout(scale: Double(percent) / 100)
        let scale = layout.rabbitSize.height / clip.metadata.body_h
        let rect = CGRect(x: layout.rabbitFrame.midX - clip.anchor.x * scale,
                          y: layout.rabbitFrame.minY + (clip.anchor.y - Double(clip.metadata.h)) * scale,
                          width: Double(clip.metadata.w) * scale, height: Double(clip.metadata.h) * scale)
        #expect(CGRect(origin: .zero, size: layout.panelSize).contains(rect), "Flames and laptop must fit at \(percent)%")
    }
}

// 붙잡힌 모션의 표시 자세와 마우스 기준점이 맞는지 검증한다.
@Test @MainActor func heldMotionKeepsTheCursorLandmarkOnTheDisplayedPose() {
    let clip = ZicSprites.shared.clip(.drag)
    #expect(clip.metadata.grab_anchors?.count == clip.frames.count)
    #expect(clip.metadata.grab_scales?.count == clip.frames.count)
    #expect(clip.grabRotationDegrees > 0 && clip.grabRotationDegrees < 45)
    for cycle in 0..<2 {
        for index in clip.frames.indices {
            let elapsed = Double(cycle) * clip.duration + (Double(index)+0.25) * clip.metadata.delay_ms / 1000
            let displayed = clip.frameIndex(elapsed: elapsed, animate: true)
            #expect(displayed == index)
            #expect(clip.frame(elapsed: elapsed, animate: true) === clip.frames[index])
            let point = clip.grabAnchor(frameIndex: displayed)
            #expect(abs(Double(point.x) - (clip.metadata.grab_anchors?[index][0] ?? .nan)) < 0.001)
            #expect(abs(Double(point.y) - (clip.metadata.grab_anchors?[index][1] ?? .nan)) < 0.001)
            #expect((0.8...1.0).contains(clip.grabScale(frameIndex: displayed)))
        }
    }
    let stillIndex = clip.frameIndex(elapsed: clip.duration/2, animate: false)
    #expect(stillIndex == 0)
    #expect(clip.grabAnchor(frameIndex: stillIndex) == clip.grabAnchor)
    #expect(clip.grabScale(frameIndex: stillIndex) == 1)
    // Older resources without per-frame landmarks retain their static fallback.
    let idle = ZicSprites.shared.clip(.idle)
    #expect(idle.grabAnchor(frameIndex: 7) == idle.grabAnchor)
}

// 8방향 걷기의 방향별 그림과 프레임 주기 일관성을 검증한다.
@Test @MainActor func allEightDirectionsUseMatchingViewsAtOneWalkingCadence() {
    let sprites = ZicSprites.shared
    let duration = sprites.clip(.walk).duration
    for direction in WalkDirection.allCases {
        let state = ZicMotion.walking(direction)
        #expect(state.isWalking)
        #expect(abs(sprites.clip(state).duration - duration) < 0.01)
    }
    #expect(ZicMotion.walking(.north) == .walkBack)
    #expect(ZicMotion.walking(.south) == .walkFront)
    #expect(ZicMotion.walking(.east) == .walkSide)
    #expect(WalkDirection.west.mirrored && !WalkDirection.east.mirrored)
    #expect(ZicMotion.walking(.northWest) == .walkBackDiagonal)
    #expect(ZicMotion.walking(.southEast) == .walk)
}
