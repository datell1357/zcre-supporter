// 기능 분류: 디버그 전용 모션 테스트 · 스크롤 없는 방향 선택
import SwiftUI

struct MotionTestView: View {
    static let size = CGSize(width: 520, height: 560)
    var store: CompanionStore
    var motion: PetMotion
    var run: (PetActionTest) -> Void
    var stop: () -> Void
    var showMenuStatus: () -> Void = {}

    private let directions: [PetActionTest?] = [.upLeft, .up, .upRight, .left, nil, .right, .downLeft, .down, .downRight]
    private var canRun: Bool { store.debugModeEnabled && store.preferences.petVisible && !store.isSleeping }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("지크 모션 테스트").font(.system(size: 22, weight: .bold))
                    Text("동작을 선택하면 바로 재생해요.").font(.system(size: 11)).foregroundStyle(BunnyTheme.muted)
                }
                Spacer()
                Text("디버그 모드").font(.system(size: 10, weight: .medium)).foregroundStyle(BunnyTheme.accent)
            }
            if !store.preferences.petVisible {
                HStack {
                    Text("지크가 숨겨져 있어요.").font(.system(size: 11))
                    Spacer()
                    Button("지크 보이기") { store.preferences.petVisible = true }.buttonStyle(ZCREButtonStyle())
                }
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("8방향 이동 · 2초").font(.system(size: 12, weight: .semibold))
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(72), spacing: 7), count: 3), spacing: 7) {
                        ForEach(directions.indices, id: \.self) { index in
                            if let action = directions[index] {
                                Button { run(action) } label: {
                                    Text(directionSymbol(action)).font(.system(size: 23, weight: .medium))
                                        .frame(width: 48, height: 31)
                                }.buttonStyle(ZCREButtonStyle()).disabled(!canRun)
                                    .help(action.title).accessibilityLabel(action.title)
                            } else {
                                Button(action: stop) { Text("중지").frame(width: 48, height: 31) }
                                    .buttonStyle(ZCREButtonStyle()).disabled(motion.testLabel == nil)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("표정과 동작").font(.system(size: 12, weight: .semibold))
                    ForEach([PetActionTest.idle, .dragLeft, .dragRight, .working, .complete, .failed, .wave], id: \.rawValue) { action in
                        Button { run(action) } label: {
                            Text(action.title).frame(maxWidth: .infinity, minHeight: 24)
                        }.buttonStyle(ZCREButtonStyle()).disabled(!canRun)
                    }
                }.frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(motion.testLabel.map { "재생 중 · \($0)" } ?? "대기 중")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(BunnyTheme.accent)
                Text("이동은 2초, 작업 중은 상단 바와 함께 6초 재생해요.\n완료·실패·인사는 한 번 재생하며 작업·크레딧·알림은 바뀌지 않아요.")
                    .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted).lineSpacing(3)
            }
            Button("상단 바 현황 열기", action: showMenuStatus)
                .buttonStyle(ZCREButtonStyle()).disabled(!store.debugModeEnabled)
            Spacer(minLength: 0)
        }.padding(22).frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
            .background(BunnyTheme.background).foregroundStyle(BunnyTheme.foreground)
            .preferredColorScheme(.dark)
    }

    /// 각 이동 테스트에 대응하는 방향 화살표를 선택한다.
    private func directionSymbol(_ action: PetActionTest) -> String {
        switch action {
        case .upLeft: "↖"
        case .up: "↑"
        case .upRight: "↗"
        case .left: "←"
        case .right: "→"
        case .downLeft: "↙"
        case .down: "↓"
        case .downRight: "↘"
        default: ""
        }
    }
}
