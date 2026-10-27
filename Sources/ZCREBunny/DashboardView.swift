// 기능 분류: 상세 현황 · 크레딧 · 보관된 알림과 작업 목록
import SwiftUI
import ZCRECore

struct DashboardView: View {
    @Bindable var store: CompanionStore
    var showSettings: () -> Void
    var close: () -> Void
    var size = CGSize(width: 370, height: 620)

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if store.snapshot == nil { welcome } else { credits }
                    RecentAlertsView(store: store, title: "전체 알림", close: close)
                    if store.snapshot != nil { jobs }
                    if store.notificationStatus == .denied {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Mac 알림이 꺼져 있어요", systemImage: "bell.slash")
                                .font(.system(size: 12, weight: .semibold))
                            Text("작업 완료 배너를 받으려면 \(AppInfo.name)의 알림을 허용해 주세요.")
                                .font(.system(size: 11)).foregroundStyle(BunnyTheme.muted)
                            Button("알림 설정 열기") { store.openNotificationSettings() }
                                .buttonStyle(ZCREButtonStyle())
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(BunnyTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if case .delayed(let message) = store.connection {
                        Label(message, systemImage: "wifi.exclamationmark")
                            .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if store.isDemo {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("미리보기 · 실제 계정과 무관한 예시예요", systemImage: "sparkles")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(BunnyTheme.accent)
                            HStack {
                                Button("완료 알림 체험") { store.simulateCompletion() }
                                Spacer()
                                Button("ZCRE 연결") { store.connect() }
                            }.buttonStyle(ZCREButtonStyle())
                        }.padding(12).background(BunnyTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    }
                    companion
                }.padding(.horizontal, 22).padding(.bottom, 18)
            }.scrollIndicators(.hidden)
            footer
        }
        .frame(width: size.width, height: size.height)
        .background(BunnyTheme.background)
        .foregroundStyle(BunnyTheme.foreground)
        .preferredColorScheme(.dark)
        .tint(BunnyTheme.foreground)
    }

    // 앱 이름과 연결 상태를 표시한다.
    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(AppInfo.name).font(.system(size: 20, weight: .heavy)).tracking(-0.8)
                    Text("지크").font(.system(size: 10, weight: .medium)).foregroundStyle(BunnyTheme.accent)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(BunnyTheme.accent.opacity(0.08), in: Capsule())
                        .overlay(Capsule().strokeBorder(BunnyTheme.accent.opacity(0.35)))
                }
                Text("크레딧과 작업 현황").font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
            }
            Spacer()
            Button(action: showSettings) { Image(systemName: "slider.horizontal.3").frame(width: 28, height: 28) }
                .buttonStyle(.plain).foregroundStyle(BunnyTheme.muted).help("지크 설정").accessibilityLabel("지크 설정")
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 11)).frame(width: 20, height: 28) }
                .buttonStyle(.plain).foregroundStyle(BunnyTheme.muted).accessibilityLabel("현황판 닫기")
        }
    }

    // 검증된 잔액과 진행 개수를 표시한다.
    private var credits: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("사용 가능 크레딧").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                Spacer()
                Circle().fill(store.isStale ? .orange : BunnyTheme.success).frame(width: 5, height: 5)
                Text(store.isDemo ? "미리보기" : store.connection.label).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.75))
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(store.creditText).help(store.snapshot.map { "크레딧 확인: \($0.balanceFetchedAt.formatted(date: .omitted, time: .standard))" } ?? "연결 대기").font(.system(size: 45, weight: .semibold, design: .rounded)).tracking(-1.8).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                Text("Credit").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 0)
            }
            HStack {
                Label("예약 \(CreditBalance.format(store.snapshot?.balance.reserved ?? 0))", systemImage: "clock")
                Spacer()
                Text("총 \(CreditBalance.format(store.snapshot?.balance.total ?? 0))")
            }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.62))
        }
        .padding(20)
        .background(BunnyTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BunnyTheme.border))
    }

    // 진행 중 작업을 우선 표시하고 이력 표시량을 제한한다.
    private var jobs: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("나의 작업").font(.system(size: 13, weight: .semibold))
                if !store.activeJobs.isEmpty {
                    Text("\(store.activeJobs.count) 진행 중").font(.system(size: 10, weight: .medium)).foregroundStyle(BunnyTheme.accent)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(BunnyTheme.accent.opacity(0.08), in: Capsule())
                }
                Spacer()
                Button("전체 보기 ↗") { CompanionStore.openWebsite(path: "/history") }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
            }
            let visible = Array((store.activeJobs + (store.snapshot?.jobs.filter { !$0.status.isActive } ?? [])).prefix(5))
            if visible.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle").font(.system(size: 24)).foregroundStyle(BunnyTheme.success)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("아직 진행 중인 작업이 없어요").font(.system(size: 12, weight: .medium))
                        Text("ZCRE에서 시작하면 여기서 알려드려요").font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                    }
                }.padding(.vertical, 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(visible) { job in
                        JobRow(job: job)
                        if job.id != visible.last?.id { Divider().overlay(.white.opacity(0.03)).padding(.leading, 49) }
                    }
                }.padding(.horizontal, 12).background(BunnyTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BunnyTheme.border))
            }
            if store.snapshot?.historyTruncated == true {
                Text("최근 1,000개 기록 기준 · 이전 작업은 웹에서 확인해 주세요")
                    .font(.system(size: 10)).foregroundStyle(.orange)
            }
        }
    }

    // 처음 사용자를 계정 연결 또는 로컬 데모로 안내한다.
    private var welcome: some View {
        VStack(spacing: 14) {
            RabbitView(animate: false).frame(width: 106, height: 128).padding(.top, 9)
            Text("작업 곁에, 지크.").font(.system(size: 22, weight: .bold, design: .rounded))
            Text("크레딧과 작업을 살펴보고\n완성되는 순간 알려드릴게요.")
                .font(.system(size: 12)).lineSpacing(5).multilineTextAlignment(.center).foregroundStyle(BunnyTheme.muted)
            Button { store.connect() } label: {
                HStack { Image(systemName: "link"); Text("ZCRE 계정 연결"); Spacer(); Image(systemName: "arrow.up.right") }
                    .font(.system(size: 13, weight: .semibold)).padding(13).background(BunnyTheme.foreground, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(BunnyTheme.ink)
            }.buttonStyle(.plain).padding(.top, 5)
            Button("연결 전에 미리 둘러보기") { store.enterDemo() }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(BunnyTheme.muted)
            Text("앱에서 한 번 로그인해 주세요.\n이 앱은 크레딧을 사용하거나 작업을 생성하지 않아요.")
                .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted.opacity(0.8)).multilineTextAlignment(.center).lineSpacing(3)
        }.padding(20).frame(maxWidth: .infinity).background(BunnyTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BunnyTheme.border))
    }

    // 지크 표시와 설정 진입을 제공한다.
    private var companion: some View {
        HStack(spacing: 11) {
            Image(systemName: store.activeJobs.isEmpty ? "moon.stars" : "sparkles").foregroundStyle(BunnyTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.lastEvent ?? store.companionMessage).font(.system(size: 11, weight: .medium))
                Text(store.preferences.petVisible ? "지크를 끌어서 원하는 곳에 놓아보세요" : "지크 숨김 · 상단 바에서 알림을 확인하세요").font(.system(size: 9)).foregroundStyle(BunnyTheme.muted)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 2)
    }
    // 작업·잔액 갱신 시각과 사용자가 요청하는 새로고침을 제공한다.
    private var footer: some View {
        HStack(spacing: 8) {
            if let snapshot = store.snapshot {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) { Text("작업"); Text(snapshot.fetchedAt, style: .relative).monospacedDigit(); Text("전") }
                    HStack(spacing: 2) { Text("크레딧"); Text(snapshot.balanceFetchedAt, style: .relative).monospacedDigit(); Text("전") }
                }
            } else { Text("개인 워크스페이스와 연결해요") }
            Spacer()
            Button { store.refreshSoon(forceBalance: true) } label: {
                Image(systemName: "arrow.clockwise").opacity(store.isRefreshing ? 0.4 : 1)
            }.buttonStyle(.plain).disabled(store.isRefreshing || store.isDemo).accessibilityLabel("현황 새로고침")
            Button("ZCRE 열기 ↗") { CompanionStore.openWebsite() }.buttonStyle(.plain).padding(.leading, 8)
        }.font(.system(size: 9)).foregroundStyle(BunnyTheme.muted).padding(.horizontal, 22).padding(.vertical, 14)
            .background(BunnyTheme.background)
            .overlay(alignment: .top) { Rectangle().fill(BunnyTheme.border).frame(height: 1) }
    }
}

private struct JobRow: View {
    let job: GenerationJob
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: job.symbol).font(.system(size: 14)).foregroundStyle(BunnyTheme.foreground)
                .frame(width: 34, height: 34).background(BunnyTheme.elevated, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(job.displayName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text(job.createdAt, style: .relative).font(.system(size: 9)).foregroundStyle(BunnyTheme.muted)
            }
            Spacer(minLength: 6)
            if job.status.isActive { ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 12) }
            Text(job.status.label).font(.system(size: 10, weight: .medium))
                .foregroundStyle(job.status == .succeeded ? BunnyTheme.accent : job.status == .failed ? .orange : BunnyTheme.foreground)
        }.padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
