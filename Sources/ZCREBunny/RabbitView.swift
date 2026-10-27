// 기능 분류: 지크 프레임 렌더링 · 크기와 목덜이 기준점 유지
import SwiftUI
import ZCRECore

struct RabbitView: View {
    var moving = false
    var working = false
    var workingMirrored = false
    var dragging = false
    var dragMirrored = false
    var celebrationStart: Date?
    var failureStart: Date?
    var waveStart: Date?
    var direction: WalkDirection = .east
    var testMotion: ZicMotion?
    var animate = true
    @State private var motionStartedAt = Date.now
    @State private var celebrationAnimating = false
    @State private var failureAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 현재 모션을 로컬 스프라이트로 그린다. 타임라인은 서버 조회와 무관하며 숨김·동작 줄이기 시 멈춘다.
    var body: some View {
        let sprites = ZicSprites.shared
        let hasAnimation = ZicMotion.allCases.contains { sprites.hasAnimation($0) }
        let activeMotion = moving || working || dragging || celebrationAnimating || failureAnimating || waveStart != nil || (testMotion != nil && testMotion != .idle)
        TimelineView(.animation(minimumInterval: activeMotion ? 1.0 / 24 : 1.0 / 12, paused: !animate || reduceMotion || !hasAnimation)) { timeline in
            let celebrationAge = celebrationStart.map { timeline.date.timeIntervalSince($0) }
            let celebrating = celebrationAge.map { $0 >= 0 && $0 < sprites.clip(.complete).duration } ?? false
            let failureAge = failureStart.map { timeline.date.timeIntervalSince($0) }
            let failing = failureAge.map { $0 >= 0 && $0 < sprites.clip(.cry).duration } ?? false
            let waveAge = waveStart.map { timeline.date.timeIntervalSince($0) }
            let waving = waveAge.map { $0 >= 0 && $0 < sprites.clip(.wave).duration } ?? false
            let state = ZicMotion.resolve(test: testMotion, dragging: dragging, celebrating: celebrating, working: working, moving: moving, direction: direction, failing: failing, waving: waving)
            let clip = sprites.clip(state)
            let elapsed = state == .complete ? celebrationAge ?? 0 : state == .cry ? failureAge ?? 0 : state == .wave ? waveAge ?? timeline.date.timeIntervalSince(motionStartedAt) : timeline.date.timeIntervalSince(motionStartedAt)
            let frameIndex = clip.frameIndex(elapsed: elapsed, animate: animate && !reduceMotion)
            let frame = clip.frames[frameIndex]
            GeometryReader { geometry in
                // 앞발을 드는 모션에서도 기준 신장은 일정하게 유지한다.
                let scale = geometry.size.height / clip.metadata.body_h * (dragging ? clip.grabScale(frameIndex: frameIndex) : 1)
                let extra = geometry.size.height * (state == .complete ? 0.55 : 0.4)
                let pivot = dragging ? clip.grabAnchor(frameIndex: frameIndex) : clip.anchor
                let targetY = dragging ? geometry.size.height / 2 : geometry.size.height
                Canvas { context, _ in
                    context.translateBy(x: geometry.size.width / 2 + extra, y: targetY + extra)
                    if dragging && dragMirrored || state.isWalking && direction.mirrored || state == .working && workingMirrored {
                        // 이미지 상자 대신 마우스 또는 서 있는 중심을 기준으로 좌우 반전한다.
                        context.scaleBy(x: -1, y: 1)
                    }
                    if dragging { context.rotate(by: .degrees(clip.grabRotationDegrees)) }
                    let rect = CGRect(x: -pivot.x * scale,
                                      y: -pivot.y * scale,
                                      width: Double(clip.metadata.w) * scale,
                                      height: Double(clip.metadata.h) * scale)
                    context.draw(Image(nsImage: frame), in: rect)
                }
                .frame(width: geometry.size.width + extra * 2, height: geometry.size.height + extra * 2)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .task(id: celebrationStart) {
            guard let celebrationStart else { celebrationAnimating = false; return }
            let remaining = sprites.clip(.complete).duration - Date.now.timeIntervalSince(celebrationStart)
            guard remaining > 0 else { celebrationAnimating = false; return }
            celebrationAnimating = true
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            celebrationAnimating = false
        }
        .task(id: failureStart) {
            guard let failureStart else { failureAnimating = false; return }
            let remaining = sprites.clip(.cry).duration - Date.now.timeIntervalSince(failureStart)
            guard remaining > 0 else { failureAnimating = false; return }
            failureAnimating = true
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            failureAnimating = false
        }
        .onChange(of: moving) { motionStartedAt = .now }
        .onChange(of: working) { motionStartedAt = .now }
        .onChange(of: dragging) { motionStartedAt = .now }
        .onChange(of: testMotion) { motionStartedAt = .now }
        .accessibilityLabel("검정 비니를 쓴 지크 토끼")
    }
}
