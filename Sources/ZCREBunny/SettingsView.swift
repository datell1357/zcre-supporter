// 기능 분류: 지크 표시 · 알림 · 계정 · 디버그 설정 화면
import AppKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Bindable var store: CompanionStore
    var resetPosition: () -> Void
    var loginItem = LoginItemController()
    var showMotionTests: () -> Void = {}
    @State private var debugCode = ""
    @State private var showDebugCode = false
    @State private var debugCodeError = false

    var body: some View {
        @Bindable var prefs = store.preferences
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("지크 설정").font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("편안한 작업 리듬에 맞춰 주세요.").font(.system(size: 12)).foregroundStyle(BunnyTheme.muted)
                    }
                    Spacer()
                    RabbitView(celebrationStart: store.celebrationStart, failureStart: store.failureStart).frame(width: 54, height: 66)
                }
                section("바탕화면") {
                    Toggle("바탕화면에 지크 보이기", isOn: $prefs.petVisible)
                    Text("숨겨도 크레딧과 작업은 계속 확인해요. 상단 바에서 지크를 다시 표시할 수 있어요.")
                        .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                    Toggle("산책 활성화", isOn: $prefs.roaming)
                    Toggle("메뉴 막대에 크레딧 표시", isOn: $prefs.showMenuCredits)
                    Divider()
                    HStack { Text("지크 크기"); Spacer(); Text("\(Int((prefs.petScale * 100).rounded()))%\(abs(prefs.petScale - 1) < 0.001 ? " · 기본" : "")").foregroundStyle(BunnyTheme.muted).monospacedDigit() }
                    Slider(value: $prefs.petScale, in: 0.7...1.5, step: 0.1).accessibilityLabel("지크 크기")
                    Text("말풍선 글씨 크기는 지크 크기와 관계없이 유지돼요.").font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                    Button("지크를 화면 아래로 데려오기", action: resetPosition).buttonStyle(.plain).foregroundStyle(BunnyTheme.accent)
                }
                section("지크 효과음") {
                    Toggle("지크 효과음 사용", isOn: $prefs.petSounds)
                    HStack {
                        Text("효과음 음량")
                        Spacer()
                        Text("\(Int((prefs.petSoundVolume * 100).rounded()))%")
                            .foregroundStyle(BunnyTheme.muted).monospacedDigit()
                    }
                    Slider(value: $prefs.petSoundVolume, in: 0...1, step: 0.01)
                        .disabled(!prefs.petSounds)
                        .accessibilityLabel("지크 효과음 음량")
                        .accessibilityValue("\(Int((prefs.petSoundVolume * 100).rounded()))퍼센트")
                    Text("붙잡을 때 효과음과 작업 중 짧은 타자 소리가 나요. 다른 앱에서 소리를 재생하거나 통화 중이면 타자음은 쉬어요.")
                        .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                    Text("macOS 알림 소리는 아래 알림 설정에서 따로 선택해요.")
                        .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                }
                section("알림") {
                    Toggle("지크 숨김 시 상단 바 배너", isOn: $prefs.menuBarAlerts)
                    Text("완료·실패·크레딧 부족 알림이 상단 바 아래에 떠요. 지난 내용은 최근 알림에서 확인할 수 있어요.")
                        .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                    Toggle("작업 완료", isOn: $prefs.completionAlerts)
                    Toggle("작업 실패", isOn: $prefs.failureAlerts)
                    Toggle("크레딧 부족", isOn: $prefs.lowCreditAlerts)
                    if prefs.lowCreditAlerts {
                        Stepper("\(Int(prefs.lowCreditThreshold)) Credit 이하", value: $prefs.lowCreditThreshold, in: 0...10000, step: 10)
                    }
                    Toggle("알림 소리", isOn: $prefs.sound)
                    Divider()
                    HStack {
                        Circle().fill(store.notificationStatus == .authorized ? BunnyTheme.success : .orange).frame(width: 6, height: 6)
                        Text(notificationLabel).font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                        Spacer()
                        if store.notificationStatus == .notDetermined {
                            Button("알림 허용") { Task { await store.enableNotifications() } }.buttonStyle(ZCREButtonStyle())
                        } else {
                            Button("알림 설정 열기") { store.openNotificationSettings() }.buttonStyle(ZCREButtonStyle())
                        }
                        Button("테스트") { Task { await store.testNotification() } }.buttonStyle(ZCREButtonStyle()).disabled(store.focusActive)
                    }
                }
                section("작업 종류별 알림") {
                    Toggle("이미지 작업", isOn: $prefs.imageJobAlerts)
                    Toggle("영상 작업", isOn: $prefs.videoJobAlerts)
                    Toggle("업스케일 작업", isOn: $prefs.upscaleJobAlerts)
                    Toggle("오디오 작업", isOn: $prefs.audioJobAlerts)
                    Toggle("기타 작업", isOn: $prefs.otherJobAlerts)
                    Text("완료·실패 알림에 적용돼요. 업스케일은 이미지·영상과 따로 설정해요. 끈 작업도 현황과 기록에는 남아요.")
                        .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                }
                section("집중 모드") {
                    Toggle("지금 집중하기", isOn: $prefs.focusNow)
                    Toggle("매일 정해진 시간에 집중", isOn: $prefs.focusSchedule)
                    if prefs.focusSchedule {
                        DatePicker("시작", selection: minuteBinding($prefs.focusStartMinute), displayedComponents: .hourAndMinute)
                        DatePicker("종료", selection: minuteBinding($prefs.focusEndMinute), displayedComponents: .hourAndMinute)
                        Text("Mac의 현지 시각을 기준으로 해요. 자정을 넘겨 설정할 수 있고, 시작과 종료가 같으면 하루 종일 적용돼요.")
                            .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                    }
                    Text(store.focusActive ? "지금은 조용히 기록하고 있어요" : "현재 집중 모드가 꺼져 있어요")
                        .foregroundStyle(BunnyTheme.accent)
                    Text("알림 배너·시스템 알림·완료와 실패 반응·효과음을 쉬어요. 크레딧과 작업 갱신, 알림 기록은 유지돼요. 종료 후 지난 알림을 몰아서 띄우지 않아요. macOS 집중 모드와는 별도 설정이에요.")
                        .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                }
                section("계정") {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(store.isDemo ? "미리보기 모드" : store.snapshot?.workspaceName ?? "아직 연결되지 않았어요")
                            Text("로그인은 앱의 웹 세션에만 보관돼요.").font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                        }
                        Spacer()
                        Button("계정 열기") { store.connect() }.buttonStyle(ZCREButtonStyle())
                    }
                    HStack {
                        Button(store.isDemo ? "미리보기 종료" : "미리보기 체험") { if store.isDemo { store.leaveDemo() } else { store.enterDemo() } }
                            .buttonStyle(.plain).foregroundStyle(BunnyTheme.accent)
                        Spacer()
                        Button("연결 해제") { store.disconnect() }.buttonStyle(.plain).foregroundStyle(BunnyTheme.muted).disabled(store.isDemo)
                    }
                }
                section("앱") {
                    Toggle("Mac 로그인 시 자동 실행", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                    Text(loginItem.label).font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                    if loginItem.requiresApproval || loginItem.message != nil {
                        if let message = loginItem.message { Text(message).font(.system(size: 10)).foregroundStyle(.orange) }
                        Button("로그인 항목 설정 열기") { loginItem.openSettings() }.buttonStyle(ZCREButtonStyle())
                    }
                    Divider()
                    Button("진단 정보 내보내기…") { DiagnosticsExporter.export(store: store, loginItem: loginItem) }
                        .buttonStyle(.plain).foregroundStyle(BunnyTheme.accent)
                    Text("앱·macOS 버전과 연결 상태를 저장해요. 계정, 잔액과 작업 내용은 포함하지 않아요.")
                        .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                }
                section("디버그 모드") {
                    if store.debugModeEnabled {
                        HStack {
                            Label("활성화됨", systemImage: "checkmark.circle.fill").foregroundStyle(BunnyTheme.accent)
                            Spacer()
                            Button("끄기") { store.disableDebugMode() }.buttonStyle(ZCREButtonStyle())
                        }
                        Button("지크 모션 테스트 열기", action: showMotionTests).buttonStyle(ZCREButtonStyle(prominent: true))
                        Text("앱을 종료하면 디버그 모드가 꺼져요.").font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                    } else if showDebugCode {
                        HStack {
                            SecureField("활성화 코드", text: $debugCode).textFieldStyle(.roundedBorder)
                                .onSubmit(unlockDebugMode)
                                .accessibilityLabel("디버그 모드 활성화 코드")
                            Button("활성화", action: unlockDebugMode).buttonStyle(ZCREButtonStyle())
                                .disabled(debugCode.isEmpty)
                            Button("취소") { showDebugCode = false; debugCode = ""; debugCodeError = false }
                                .buttonStyle(.plain)
                        }
                        if debugCodeError { Text("코드가 일치하지 않아요.").font(.system(size: 10)).foregroundStyle(.orange) }
                    } else {
                        Button("디버그 모드 활성화") { showDebugCode = true }.buttonStyle(ZCREButtonStyle())
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(AppInfo.name) \(AppInfo.version) (\(AppInfo.build)) · 베타").font(.system(size: 11, weight: .medium))
                    Text("작업은 5초, 크레딧은 60초마다 확인해요.\n작업 상태가 바뀌면 크레딧도 바로 확인해요.\nMac이 잠자거나 앱이 종료되면 알림도 쉬어요.")
                        .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted).lineSpacing(4)
                    Button("앱 종료") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(BunnyTheme.muted).padding(.top, 6)
                }
            }.padding(25)
        }.frame(width: 430, height: 700).background(BunnyTheme.background).foregroundStyle(BunnyTheme.foreground).preferredColorScheme(.dark).tint(BunnyTheme.accent)
            .toggleStyle(SwitchToggleStyle(tint: BunnyTheme.accent)).controlSize(.small)
            .task { loginItem.refresh(); await store.refreshNotificationStatus() }
    }
    /// 날짜를 저장하지 않고 시·분만 보관해 매일 동일한 현지 시간에 적용한다.
    private func minuteBinding(_ value: Binding<Int>) -> Binding<Date> {
        Binding(get: {
            Calendar.autoupdatingCurrent.date(bySettingHour: value.wrappedValue / 60, minute: value.wrappedValue % 60, second: 0, of: .now) ?? .now
        }, set: {
            let parts = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: $0)
            value.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
    }
    /// 입력 코드를 저장소에 전달하고 성공 시 입력값을 지우며 실패 시 안내를 표시한다.
    private func unlockDebugMode() {
        if store.unlockDebugMode(code: debugCode) {
            debugCode = ""; showDebugCode = false; debugCodeError = false
        } else { debugCodeError = true }
    }
    // macOS 권한 상태와 앱 내부 알림을 구분해 안내한다.
    private var notificationLabel: String {
        switch store.notificationStatus {
        case .authorized, .provisional: "macOS 알림 사용 중"
        case .denied: "시스템 알림이 꺼져 있어요"
        default: "앱 내 알림 사용 중"
        }
    }
    /// 설정 항목을 공통 제목·카드 스타일로 묶는다.
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(BunnyTheme.muted)
            VStack(alignment: .leading, spacing: 13, content: content).font(.system(size: 12)).padding(15)
                .frame(maxWidth: .infinity, alignment: .leading).background(BunnyTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BunnyTheme.border))
        }
    }
}
