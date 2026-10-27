// 기능 분류: 메뉴 막대 현황 · 최근 알림 10개 · 공개 서비스 상태
import SwiftUI

struct MenuBarView: View {
    static let preferredSize = CGSize(width: 980, height: 600)
    static let recentAlertLimit = 10
    @Bindable var store: CompanionStore
    var serviceStatus: ServiceStatusStore
    var showDashboard: () -> Void
    var showSettings: () -> Void
    var close: () -> Void
    var size: CGSize

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(AppInfo.name).font(.system(size: 17, weight: .heavy)).tracking(-0.6)
                Text(store.isDemo ? "미리보기" : store.connection.label)
                    .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .padding(.leading, 8).accessibilityLabel("현황 닫기")
            }.buttonStyle(.plain).padding(18)
            HStack(alignment: .top, spacing: 0) {
                ActiveJobsView(store: store).frame(width: size.width * 0.31)
                Rectangle().fill(BunnyTheme.border).frame(width: 1)
                accountPanel.frame(width: size.width * 0.35)
                Rectangle().fill(BunnyTheme.border).frame(width: 1)
                ServiceStatusView(status: serviceStatus).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(width: size.width, height: size.height)
            .background(BunnyTheme.background).foregroundStyle(BunnyTheme.foreground)
            .preferredColorScheme(.dark).tint(BunnyTheme.foreground)
    }

    // 계정 요약과 최근 알림 10개를 표시하고 전체 보관 이력은 상세 현황으로 연결한다.
    private var accountPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("현재 크레딧").font(.system(size: 11)).foregroundStyle(BunnyTheme.muted)
                            Text(store.creditText).help(store.snapshot.map { "크레딧 확인: \($0.balanceFetchedAt.formatted(date: .omitted, time: .standard))" } ?? "연결 대기").font(.system(size: 30, weight: .semibold)).monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            Text("작업 중").font(.system(size: 11)).foregroundStyle(BunnyTheme.muted)
                            Text(store.snapshot == nil ? "—" : "\(store.activeJobs.count)개")
                                .font(.system(size: 20, weight: .semibold)).monospacedDigit()
                        }
                    }
                    if store.snapshot == nil {
                        Button("ZCRE 계정 연결") { close(); store.connect() }.buttonStyle(ZCREButtonStyle())
                    }
                    if store.isStale {
                        Label(store.delayMessage, systemImage: "wifi.exclamationmark")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                    }
                    Button {
                        store.preferences.petVisible.toggle()
                    } label: {
                        HStack {
                            Image(systemName: store.preferences.petVisible ? "eye.slash" : "eye")
                            Text(store.preferences.petVisible ? "지크 숨기기" : "지크 보이기")
                            Spacer()
                            Text(store.preferences.petVisible ? "바탕화면" : "상단 바에서 알림")
                                .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                        }.padding(12).background(BunnyTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                    Button(action: showSettings) {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                            Text("설정")
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10))
                        }.padding(.horizontal, 12).padding(.vertical, 8)
                    }.buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                    Divider()
                    RecentAlertsView(store: store, maximumCount: Self.recentAlertLimit, showAll: showDashboard, close: close)
                }.padding(.horizontal, 18).padding(.bottom, 16)
            }
            HStack {
                Button("상세 현황", action: showDashboard)
                Spacer()
                Button("ZCRE 열기 ↗") { CompanionStore.openWebsite() }
            }.buttonStyle(.plain).font(.system(size: 11)).padding(16)
                .overlay(alignment: .top) { Rectangle().fill(BunnyTheme.border).frame(height: 1) }
        }
    }
}
