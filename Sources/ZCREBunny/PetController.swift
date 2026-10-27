// 기능 분류: 지크 창 배치 · 드래그 · 랜덤 산책 · 모션 테스트
import AppKit
import SwiftUI
import Observation
import ZCRECore

@MainActor @Observable
final class PetMotion {
    var moving = false
    var dragging = false
    var dragMirrored = false
    var workingMirrored = false
    var waveStart: Date?
    var direction: WalkDirection = .east
    var testMotion: ZicMotion?
    var testLabel: String?
}

private final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// 수동 드래그 위치를 macOS의 자동 창 경계 제한으로 보정하지 않는다.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class PetController {
    let panel: NSPanel
    let motion = PetMotion()
    private let store: CompanionStore
    private let sounds = PetSoundController()
    private var timer: Timer?
    private var timerInterval: TimeInterval?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var pointerOverPet = false
    private var walkTarget: CGPoint?
    private var nextWalk = Date.now.addingTimeInterval(7)
    private var dragAnchor: PetDragAnchor?
    private var dragFacing: PetDragFacing?
    private var actionTest: (action: PetActionTest, startedAt: TimeInterval, movement: PetMovementTest?)?
    private var testCelebrationStart: Date?
    private var testFailureStart: Date?
    private var idleWaveSchedule = IdleWaveSchedule()
    private var idleWaveTask: Task<Void, Never>?
    private var lastScale = 0.0
    private var lastVisible = true
    private var lastWorking = false
    var paused = false { didSet { if paused { motion.moving = false }; configureTimer() } }
    var onClick: (() -> Void)?
    var onBeginDrag: (() -> Void)?
    var showSettings: (() -> Void)?
    var showMotionTests: (() -> Void)?
    var onTestChange: (() -> Void)?

    // MARK: - 창 구성과 표시 설정
    /// 투명 지크 창과 입력 콜백을 만들고 마지막 화면 좌표를 복원한다.
    init(store: CompanionStore) {
        self.store = store
        panel = PetPanel(contentRect: NSRect(origin: .zero, size: PetLayout(scale: store.preferences.petScale).panelSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = false; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PetView(store: store, motion: motion, click: { [weak self] in self?.onClick?() }, beginDrag: { [weak self] in self?.beginDrag($0) }, drag: { [weak self] in self?.drag($0) }, endDrag: { [weak self] in self?.endDrag() }, settings: { [weak self] in self?.showSettings?() }, showTests: { [weak self] in self?.showMotionTests?() }))
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let saved = UserDefaults.standard.string(forKey: "petOrigin") {
            setOrigin(NSPointFromString(saved))
        } else { setOrigin(NSPoint(x: visible.maxX - 320, y: visible.minY + 8)) }
        updatePreferences(); recoverPositionIfNeeded()
    }

    /// 표시·크기·작업 상태를 반영한다. 숨기거나 잠들면 모션과 마우스 관찰을 중단한다.
    func updatePreferences() {
        let prefs = store.preferences
        let working = !store.activeJobs.isEmpty
        if working != lastWorking {
            lastWorking = working
            walkTarget = nil; motion.moving = false
            if !working { nextWalk = .now.addingTimeInterval(7) }
        }
        if lastScale != prefs.petScale {
            lastScale = prefs.petScale
            let origin = panel.frame.origin
            panel.setContentSize(PetLayout(scale: lastScale).panelSize)
            setOrigin(origin)
        }
        if prefs.petVisible && !panel.isVisible { panel.orderFrontRegardless() }
        else if !prefs.petVisible && panel.isVisible { panel.orderOut(nil) }
        lastVisible = prefs.petVisible
        updateWorkingFacing()
        if !prefs.petVisible || store.isSleeping {
            stopTest()
            if dragAnchor != nil { endDrag() }
            walkTarget = nil; motion.moving = false
            timer?.invalidate(); timer = nil
            timerInterval = nil
            stopMouseTracking()
        } else {
            startMouseTracking()
            updateHitTesting()
            configureTimer()
        }
        // 숨김·잠자기 분기는 이동 타이머를 호출하지 않으므로 인사 예약도 여기서 정리한다.
        configureIdleWave()
        updateSound()
    }
    // MARK: - 마우스 입력과 클릭 영역
    /// 앱 내부와 다른 앱 위의 마우스 이동을 한 번씩 관찰한다.
    private func startMouseTracking() {
        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
                MainActor.assumeIsolated { self?.pointerChanged() }
                return event
            }
        }
        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
                MainActor.assumeIsolated { self?.pointerChanged() }
            }
        }
    }
    /// 설치한 마우스 이벤트 관찰자를 제거한다.
    private func stopMouseTracking() {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil; globalMouseMonitor = nil
    }
    /// 마우스 위치가 바뀌면 클릭 영역과 필요한 모션 타이머만 갱신한다.
    private func pointerChanged() {
        guard lastVisible, !store.isSleeping else { return }
        updateHitTesting()
        configureTimer()
    }
    /// 지크·말풍선 밖의 투명 영역에서는 클릭을 뒤쪽 앱으로 통과시킨다.
    private func updateHitTesting() {
        let mouse = NSEvent.mouseLocation
        let layout = PetLayout(scale: lastScale)
        let point = NSPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        pointerOverPet = layout.rabbitFrame.contains(point) || (store.bubble != nil && layout.bubbleFrame.contains(point))
        let ignore = dragAnchor == nil && !pointerOverPet
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
    }
    private var celebrating: Bool {
        store.celebrationStart.map { Date.now.timeIntervalSince($0) < ZicSprites.shared.clip(.complete).duration } ?? false
    }
    private var failing: Bool {
        store.failureStart.map { Date.now.timeIntervalSince($0) < ZicSprites.shared.clip(.cry).duration } ?? false
    }
    private var reacting: Bool { celebrating || failing }
    private var allowsIdleWave: Bool {
        lastVisible && !store.isSleeping && store.activeJobs.isEmpty && !paused && dragAnchor == nil &&
        !reacting && actionTest == nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 유휴 인사는 하나의 취소 가능한 예약만 사용한다. HTTP 조회나 상시 확인 타이머는 추가하지 않는다.
    private func configureIdleWave() {
        let allowed = allowsIdleWave
        let delay = idleWaveSchedule.delay(at: ProcessInfo.processInfo.systemUptime, allowed: allowed,
            idle: !motion.moving && walkTarget == nil && !pointerOverPet, randomUnit: Double.random(in: 0...1))
        guard allowed else {
            idleWaveTask?.cancel(); idleWaveTask = nil; motion.waveStart = nil
            return
        }
        if motion.waveStart != nil { return }
        guard let delay else { idleWaveTask?.cancel(); idleWaveTask = nil; return }
        guard idleWaveTask == nil else { return }
        idleWaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            guard self.allowsIdleWave, !self.motion.moving, self.walkTarget == nil, !self.pointerOverPet else {
                self.idleWaveTask = nil; self.configureTimer(); return
            }
            self.motion.waveStart = .now
            self.configureTimer()
            do { try await Task.sleep(for: .seconds(ZicSprites.shared.clip(.wave).duration)) } catch { return }
            guard !Task.isCancelled else { return }
            self.motion.waveStart = nil
            self.idleWaveSchedule.finished(at: ProcessInfo.processInfo.systemUptime, randomUnit: Double.random(in: 0...1))
            self.idleWaveTask = nil; self.nextWalk = .now.addingTimeInterval(2)
            self.configureTimer()
        }
    }
    // MARK: - 이동 타이머와 화면 복귀
    /// 실제 이동·테스트·완료 모션에 필요한 경우에만 타이머를 켜고 유휴 주기를 낮춘다.
    private func configureTimer() {
        configureIdleWave()
        updateSound()
        let interval: TimeInterval?
        if !lastVisible || store.isSleeping { interval = nil }
        else if actionTest != nil { interval = 0.05 }
        else if store.preferences.roaming && store.activeJobs.isEmpty && !paused && dragAnchor == nil && !pointerOverPet && !reacting && motion.waveStart == nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            interval = walkTarget == nil ? 1 : 0.05
        } else {
            motion.moving = false
            interval = globalMouseMonitor == nil ? 0.25 : (reacting ? 1 : nil)
        }
        guard interval != timerInterval else { return }
        timer?.invalidate(); timer = nil; timerInterval = interval
        guard let interval else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval >= 1 ? 0.1 : 0.005
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }

    /// 지크와 겹치는 면적이 가장 큰 디스플레이를 찾는다.
    private func screen() -> NSScreen? {
        let rabbit = rabbitScreenFrame
        return NSScreen.screens.max { first, second in
            let a = first.frame.intersection(rabbit), b = second.frame.intersection(rabbit)
            return max(0, a.width) * max(0, a.height) < max(0, b.width) * max(0, b.height)
        }
    }
    var visibleScreenFrame: NSRect { (screen() ?? NSScreen.main)?.visibleFrame ?? panel.frame }
    /// 긴 디버그 문구도 메뉴가 가리지 않도록 실제 텍스트 폭을 예약한다.
    var quickMenuLabelWidth: CGFloat {
        let label = motion.testLabel ?? "\(store.activeJobs.count)개의 작업 중"
        return max(110, (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width + 20)
    }

    var rabbitScreenFrame: NSRect {
        panel.convertToScreen(PetLayout(scale: store.preferences.petScale).rabbitFrame)
    }
    /// 위치를 바꾼 직후 작업 자세의 방향을 갱신한다. 이동 범위나 드래그 좌표는 제한하지 않는다.
    private func setOrigin(_ origin: CGPoint) {
        panel.setFrameOrigin(origin)
        updateWorkingFacing()
    }
    /// 다중 모니터에서도 지크가 걸쳐 있는 화면의 중앙을 기준으로 작업 자세를 뒤집는다.
    private func updateWorkingFacing() {
        guard let screen = screen() ?? NSScreen.main else { return }
        motion.workingMirrored = PetWorkFacing.mirrored(rabbit: rabbitScreenFrame, screen: screen.frame)
    }
    /// 지크 전체가 모든 화면 밖에 있을 때만 복귀시켜 의도한 가장자리 배치는 보존한다.
    func recoverPositionIfNeeded() {
        defer { updateWorkingFacing() }
        // 일부만 보이는 지크는 의도한 배치로 간주한다.
        // 연결 해제된 화면 등에 전체 형상이 사라졌을 때만 복귀시킨다.
        guard !NSScreen.screens.contains(where: { $0.frame.intersects(rabbitScreenFrame) }) else { return }
        resetPosition()
    }
    /// 테스트의 경과 시간 또는 산책 목표를 계산한다. 실제 작업 중에는 자동 산책을 멈춘다.
    private func tick() {
        guard lastVisible, !store.isSleeping else { stopTest(); motion.moving = false; return }
        updateHitTesting()
        defer { configureTimer() }
        let layout = PetLayout(scale: lastScale)
        if let test = actionTest {
            let elapsed = ProcessInfo.processInfo.systemUptime - test.startedAt
            if let movement = test.movement { setOrigin(movement.position(elapsed: elapsed)) }
            let duration = [.complete, .failed, .wave].contains(test.action) ? ZicSprites.shared.clip(test.action.motion).duration : test.action.previewDuration
            if elapsed >= duration { stopTest() }
            return
        }
        guard store.preferences.roaming, store.activeJobs.isEmpty, !paused, dragAnchor == nil, !pointerOverPet,
              !reacting, motion.waveStart == nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { motion.moving = false; return }
        if let target = walkTarget {
            let delta = CGPoint(x: target.x - panel.frame.minX, y: target.y - panel.frame.minY)
            if hypot(delta.x, delta.y) < 1.5 {
                walkTarget = nil; motion.moving = false
                nextWalk = .now.addingTimeInterval(Double.random(in: 7...16))
                savePosition()
            } else {
                motion.moving = true; motion.direction = .toward(delta)
                setOrigin(PetRoaming.step(from: panel.frame.origin, toward: target, distance: 1.5))
            }
        } else if .now >= nextWalk, let visible = screen()?.visibleFrame {
            let rabbit = layout.rabbitFrame
            let bounds = CGRect(x: visible.minX - rabbit.minX, y: visible.minY - rabbit.minY,
                                width: max(0, visible.width - rabbit.width), height: max(0, visible.height - rabbit.height))
            var random = SystemRandomNumberGenerator()
            walkTarget = PetRoaming.destination(from: panel.frame.origin, in: bounds, using: &random)
        }
    }
    // MARK: - 드래그와 효과음
    /// 클릭 시작 좌표와 좌우 방향을 저장하고 산책 목표를 취소한다.
    private func beginDrag(_ pointer: CGPoint) {
        stopTest()
        dragAnchor = PetDragAnchor(windowOrigin: panel.frame.origin, pointerOrigin: pointer)
        dragFacing = PetDragFacing(pointerX: pointer.x, mirrored: motion.direction.mirrored)
        motion.dragMirrored = motion.direction.mirrored
        walkTarget = nil
        motion.moving = false
        panel.ignoresMouseEvents = false
        configureTimer()
    }
    /// 화면 절대 좌표의 마우스 끝에 목덜이 기준점을 고정해 창 이동 피드백으로 인한 떨림을 막는다.
    private func drag(_ pointer: CGPoint) {
        guard dragAnchor != nil else { return }
        if !motion.dragging { onBeginDrag?() }
        dragFacing?.update(pointerX: pointer.x)
        motion.dragMirrored = dragFacing?.mirrored ?? false
        motion.dragging = true
        updateSound()
        setOrigin(PetDragAnchor.origin(pointer: pointer, grabPoint: PetLayout(scale: lastScale).scruffPoint))
    }
    /// 붙잡힘 상태를 해제하고 잠시 산책을 쉬며 최종 위치를 저장한다.
    private func endDrag() {
        motion.dragging = false
        dragFacing = nil
        dragAnchor = nil; nextWalk = .now.addingTimeInterval(10)
        pointerChanged()
        savePosition()
    }
    /// 사용자가 옮긴 지크의 화면 위치를 로컬 설정에 저장한다.
    private func savePosition() { UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: "petOrigin") }
    /// 화면과 같은 모션 상태를 전달한다. 짧은 재생·휴지기 예약은 소리 컨트롤러가 소유한다.
    private func updateSound() {
        let state = ZicMotion.resolve(test: motion.testMotion, dragging: motion.dragging, celebrating: celebrating,
                                      working: !store.activeJobs.isEmpty, moving: motion.moving, direction: motion.direction, failing: failing, waving: motion.waveStart != nil)
        sounds.update(motion: state, enabled: store.preferences.petSounds && !store.preferences.isFocusActive(), visible: store.preferences.petVisible,
                      sleeping: store.isSleeping, volume: store.preferences.petSoundVolume)
    }
    /// 앱 종료 시 로컬 효과음 재생을 정리한다.
    func stopSounds() { idleWaveTask?.cancel(); idleWaveTask = nil; motion.waveStart = nil; sounds.stop() }
    // MARK: - 로컬 모션 테스트
    /// 디버그 모션을 로컬에서 재생한다. 방향 테스트는 2초이며 실제 계정 작업을 만들지 않는다.
    func runTest(_ action: PetActionTest) {
        guard store.debugModeEnabled, store.preferences.petVisible, !store.isSleeping, dragAnchor == nil else { return }
        stopTest()
        walkTarget = nil
        var movement: PetMovementTest?
        if let direction = action.direction {
            let rabbit = PetLayout(scale: lastScale).rabbitFrame
            let visible = visibleScreenFrame
            // 가장자리에서는 2초 이동 경로 전체의 여유를 먼저 확보한다.
            let dx = direction.vector.x * 60, dy = direction.vector.y * 60
            let minX = visible.minX - rabbit.minX + max(0, -dx)
            let maxX = visible.maxX - rabbit.maxX - max(0, dx)
            let minY = visible.minY - rabbit.minY + max(0, -dy)
            let maxY = visible.maxY - rabbit.maxY - max(0, dy)
            let origin = CGPoint(x: min(maxX, max(minX, panel.frame.minX)), y: min(maxY, max(minY, panel.frame.minY)))
            setOrigin(origin)
            movement = PetMovementTest(origin: origin, direction: direction)
            motion.direction = direction
        }
        motion.moving = action.direction != nil
        motion.dragging = action == .dragLeft || action == .dragRight
        motion.dragMirrored = action == .dragLeft
        motion.testMotion = action.motion
        motion.testLabel = action.title
        actionTest = (action, ProcessInfo.processInfo.systemUptime, movement)
        if action == .complete {
            store.testCompletionMotion()
            testCelebrationStart = store.celebrationStart
        } else if action == .failed {
            store.testFailureMotion()
            testFailureStart = store.failureStart
        }
        onTestChange?()
        configureTimer()
    }
    /// 테스트가 만든 상태만 지우고 더 최근의 실제 완료 모션은 보존한다.
    func stopTest() {
        guard actionTest != nil else { return }
        actionTest = nil
        if let startedAt = testCelebrationStart, store.celebrationStart == startedAt { store.celebrationStart = nil }
        if let startedAt = testFailureStart, store.failureStart == startedAt { store.failureStart = nil }
        testCelebrationStart = nil
        testFailureStart = nil
        motion.testMotion = nil; motion.testLabel = nil
        motion.moving = false; motion.dragging = false
        onTestChange?()
        nextWalk = .now.addingTimeInterval(10)
        configureTimer()
        savePosition()
    }
    /// 지크를 주 화면 아래쪽으로 옮기고 복귀 위치를 저장한다.
    func resetPosition() {
        guard let screen = NSScreen.main else { return }
        stopTest()
        walkTarget = nil
        setOrigin(NSPoint(x: screen.visibleFrame.maxX - panel.frame.width - 50, y: screen.visibleFrame.minY + 8))
        savePosition()
    }
}

struct PetView: View {
    var store: CompanionStore
    var motion: PetMotion
    var click: () -> Void
    var beginDrag: (CGPoint) -> Void
    var drag: (CGPoint) -> Void
    var endDrag: () -> Void
    var settings: () -> Void
    var showTests: () -> Void
    var body: some View {
        let layout = PetLayout(scale: store.preferences.petScale)
        VStack(spacing: 0) {
            Color.clear.frame(height: 8)
            Group {
                if let bubble = store.bubble {
                    Button(action: click) {
                        Text(bubble).font(.system(size: 14, weight: .semibold)).lineSpacing(4).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(BunnyTheme.foreground).padding(.horizontal, 16).padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(BunnyTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BunnyTheme.border))
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    }.buttonStyle(.plain)
                } else { Color.clear }
            }.frame(width: layout.bubbleFrame.width, height: layout.bubbleFrame.height)
            Color.clear.frame(height: 8)
            RabbitView(moving: motion.moving, working: !store.activeJobs.isEmpty, workingMirrored: motion.workingMirrored, dragging: motion.dragging, dragMirrored: motion.dragMirrored, celebrationStart: store.celebrationStart, failureStart: store.failureStart, waveStart: motion.waveStart, direction: motion.direction, testMotion: motion.testMotion, animate: !store.isSleeping && store.preferences.petVisible)
                .frame(width: layout.rabbitSize.width, height: layout.rabbitSize.height)
                .accessibilityHidden(true)
                .overlay(PetInteractionSurface(click: click, beginDrag: beginDrag, drag: drag, endDrag: endDrag, settings: settings, showTests: showTests, debugModeEnabled: store.debugModeEnabled, roaming: store.preferences.roaming, toggleRoaming: { store.preferences.roaming.toggle() }, hide: { store.preferences.petVisible = false }))
            Color.clear.frame(height: 6)
            Group {
                if let label = motion.testLabel ?? (store.activeJobs.isEmpty ? nil : "\(store.activeJobs.count)개의 작업 중") {
                    Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(BunnyTheme.ink.opacity(0.85), in: Capsule())
                } else { Color.clear }
            }.frame(height: 22)
            Color.clear.frame(height: 8)
        }.frame(width: layout.panelSize.width, height: layout.panelSize.height)
    }
}

private struct PetInteractionSurface: NSViewRepresentable {
    var click: () -> Void
    var beginDrag: (CGPoint) -> Void
    var drag: (CGPoint) -> Void
    var endDrag: () -> Void
    var settings: () -> Void
    var showTests: () -> Void
    var debugModeEnabled: Bool
    var roaming: Bool
    var toggleRoaming: () -> Void
    var hide: () -> Void

    /// AppKit 입력 뷰를 만들고 현재 SwiftUI 콜백을 연결한다.
    func makeNSView(context: Context) -> PetMouseView { let view = PetMouseView(); updateNSView(view, context: context); return view }
    /// 입력 콜백·컨텍스트 메뉴 상태와 접근성 속성을 갱신한다.
    func updateNSView(_ view: PetMouseView, context: Context) {
        view.actions = self
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("지크. 클릭해서 간단 현황과 이미지·영상 원형 메뉴 열기")
    }
}

/// 네이티브 마우스의 화면 좌표를 사용해 창 이동량이
/// SwiftUI 제스처 좌표에 되먹임되어 떨리는 현상을 방지한다.
private final class PetMouseView: NSView {
    var actions: PetInteractionSurface?
    private var pointerDown: CGPoint?
    private var didDrag = false
    /// 앱이 비활성 상태여도 첫 클릭을 지크 조작으로 받아들인다.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// 화면 좌표로 누른 위치를 기록하고 아직 클릭인지 드래그인지 확정하지 않는다.
    override func mouseDown(with event: NSEvent) {
        let pointer = NSEvent.mouseLocation
        pointerDown = pointer; didDrag = false
        actions?.beginDrag(pointer)
    }
    /// 4포인트 이상 이동한 경우에만 드래그로 판정해 클릭과 구분한다.
    override func mouseDragged(with event: NSEvent) {
        guard let start = pointerDown else { return }
        let pointer = NSEvent.mouseLocation
        if hypot(pointer.x - start.x, pointer.y - start.y) >= 4 { didDrag = true }
        if didDrag { actions?.drag(pointer) }
    }
    /// 드래그를 끝내고 이동이 없었던 경우에만 현황판 클릭을 실행한다.
    override func mouseUp(with event: NSEvent) {
        guard pointerDown != nil else { return }
        pointerDown = nil
        actions?.endDrag()
        if !didDrag { actions?.click() }
    }
    /// 접근성 누르기 동작을 지크 현황 열기로 연결한다.
    override func accessibilityPerformPress() -> Bool { actions?.click(); return true }
    /// 현재 산책·디버그 상태에 맞는 지크 우클릭 메뉴를 구성한다.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for (title, action) in [("현황 보기", #selector(showDashboard)), (actions?.roaming == true ? "산책 비활성화" : "산책 활성화", #selector(toggleRoaming)), ("지크 숨기기", #selector(hidePet)), ("설정", #selector(showSettings))] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
        }
        if actions?.debugModeEnabled == true {
            menu.addItem(.separator())
            let item = menu.addItem(withTitle: "지크 모션 테스트…", action: #selector(showTests), keyEquivalent: "")
            item.target = self
        }
        return menu
    }
    /// 디버그 모드일 때만 모션 테스트 창을 연다.
    @objc private func showTests() { if actions?.debugModeEnabled == true { actions?.showTests() } }
    /// 지크의 간단 현황 열기 콜백을 실행한다.
    @objc private func showDashboard() { actions?.click() }
    /// 산책 활성화 설정을 전환한다.
    @objc private func toggleRoaming() { actions?.toggleRoaming() }
    /// 지크 설정 창 열기 콜백을 실행한다.
    @objc private func showSettings() { actions?.settings() }
    /// 지크를 숨기되 계정 감시 상태는 바꾸지 않는다.
    @objc private func hidePet() { actions?.hide() }
}
