// 검증 분류: 로컬 데이터와 번들 리소스 기반 회귀 테스트. 실제 생성·결제 요청은 보내지 않는다.
import Testing
import Foundation
import ZCRECore
@testable import ZCREBunny

// 테스트 메뉴가 8방향 이동과 좌우 붙잡힘을 모두 제공하는지 검증한다.
@Test func actionMenuCoversEightDirectionsAndBothHeldViews() {
    let directions = PetActionTest.allCases.compactMap(\.direction)
    #expect(Set(directions.map(\.rawValue)) == Set(WalkDirection.allCases.map(\.rawValue)))
    #expect(directions.count == 8)
    for action in PetActionTest.allCases {
        if let direction = action.direction { #expect(action.motion == ZicMotion.walking(direction)) }
    }
    #expect(PetActionTest.dragLeft.motion == .drag && PetActionTest.dragRight.motion == .drag)
    #expect(PetActionTest.idle.motion == .idle)
    #expect(PetActionTest.complete.motion == .complete)
    #expect(PetActionTest.working.motion == .working)
    #expect(PetActionTest.working.previewDuration == 6)
    #expect(PetActionTest.failed.motion == .cry)
    #expect(PetActionTest.wave.motion == .wave)
}

// 자동 인사는 유휴 자세에서만 보이며 작업·산책·드래그·완료·실패에 양보한다.
@Test func greetingNeverMasksWorkOrImportantReactions() {
    #expect(ZicMotion.resolve(test: nil, dragging: false, celebrating: false, working: false, moving: false, direction: .east, waving: true) == .wave)
    #expect(ZicMotion.resolve(test: nil, dragging: false, celebrating: false, working: true, moving: false, direction: .east, waving: true) == .working)
    #expect(ZicMotion.resolve(test: nil, dragging: false, celebrating: false, working: false, moving: true, direction: .east, waving: true) == .walkSide)
    #expect(ZicMotion.resolve(test: nil, dragging: true, celebrating: false, working: false, moving: false, direction: .east, waving: true) == .drag)
    #expect(ZicMotion.resolve(test: nil, dragging: false, celebrating: true, working: false, moving: false, direction: .east, waving: true) == .complete)
    #expect(ZicMotion.resolve(test: nil, dragging: false, celebrating: false, working: false, moving: false, direction: .east, failing: true, waving: true) == .cry)
}

// 인사는 한 번만 재생하고 지원 배율에서 손·귀가 지크 창 밖으로 잘리지 않는다.
@Test @MainActor func greetingReturnsOnceAndFitsAtEverySupportedSize() {
    let clip = ZicSprites.shared.clip(.wave)
    #expect(clip.frame(elapsed: clip.duration + 1, animate: true) === clip.frames.last)
    for percent in stride(from: 70, through: 150, by: 5) {
        let layout = PetLayout(scale: Double(percent) / 100)
        let scale = layout.rabbitSize.height / clip.metadata.body_h
        let rect = CGRect(x: layout.rabbitFrame.midX - clip.anchor.x * scale,
                          y: layout.rabbitFrame.minY + (clip.anchor.y - Double(clip.metadata.h)) * scale,
                          width: Double(clip.metadata.w) * scale, height: Double(clip.metadata.h) * scale)
        #expect(CGRect(origin: .zero, size: layout.panelSize).contains(rect))
    }
}

// 실제 실패 반응은 작업·산책보다 우선하고 드래그에는 양보한다. 반응이 끝나면 작업으로 복귀한다.
@Test func failedMotionYieldsToDraggingAndThenReturnsToWork() {
    #expect(ZicMotion.resolve(test: nil, dragging: false, celebrating: false, working: true, moving: true, direction: .east, failing: true) == .cry)
    #expect(ZicMotion.resolve(test: nil, dragging: true, celebrating: false, working: true, moving: false, direction: .east, failing: true) == .drag)
    #expect(ZicMotion.resolve(test: nil, dragging: false, celebrating: false, working: true, moving: false, direction: .east, failing: false) == .working)
}

// 작업 중에도 드래그·완료 모션이 우선하며 이후 복귀하는지 검증한다.
@Test func workingMotionYieldsToDraggingAndCompletionThenResumes() {
    #expect(ZicMotion.resolve(test: nil, dragging: false, celebrating: false, working: true, moving: true, direction: .east) == .working)
    #expect(ZicMotion.resolve(test: nil, dragging: true, celebrating: false, working: true, moving: false, direction: .east) == .drag)
    #expect(ZicMotion.resolve(test: nil, dragging: false, celebrating: true, working: true, moving: false, direction: .east) == .complete)
    #expect(ZicMotion.resolve(test: nil, dragging: false, celebrating: false, working: false, moving: true, direction: .north) == .walkBack)
    #expect(ZicMotion.resolve(test: nil, dragging: false, celebrating: false, working: false, moving: false, direction: .east) == .idle)
    #expect(ZicMotion.resolve(test: .working, dragging: false, celebrating: false, working: false, moving: false, direction: .east) == .working)
}
