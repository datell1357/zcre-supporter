// 기능 분류: 스크롤 없는 채널별 30일 팔로워 추이. 실제 수집점만 그린다.
import SwiftUI
import Charts
import AppKit

struct CreatorMetricsView: View {
    @Bindable var store: CompanionStore
    private var metrics: CreatorMetricsStore { store.creatorMetrics }
    private var online: Bool { !store.isOffline && !store.isSleeping }
    static let website = URL(string: "https://www.zcre.co.kr/zcre-next?tab=profile-metrics")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("프로필 메트릭").font(.system(size: 18, weight: .bold))
                    Text("최근 30일 · 실제 수집 기록 기준").font(.caption).foregroundStyle(BunnyTheme.muted)
                }
                Spacer()
                if let data = metrics.snapshot {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("전체 팔로워 \(count(data.totalFollowers))").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                        Text("7일 \(change(data.change7d)) · YouTube 제외").font(.caption).foregroundStyle(BunnyTheme.muted)
                    }
                }
                Button { load(manual: true) } label: {
                    if metrics.isRefreshing { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(ZCREButtonStyle()).disabled(!metrics.canRefresh || !online)
                .accessibilityLabel("프로필 메트릭 새로고침")
                .help(refreshStatus)
            }
            if store.isDemo { notice("미리보기에서는 실제 소셜 계정을 조회하지 않아요") }
            else if store.snapshot == nil {
                notice("ZCRE 계정을 연결하면 프로필 메트릭을 볼 수 있어요")
                Button("ZCRE 계정 연결") { store.connect() }.buttonStyle(ZCREButtonStyle())
            } else {
                if store.isOffline { notice("오프라인 · 마지막 확인 값을 표시해요") }
                if let error = metrics.errorMessage { notice(error + (metrics.snapshot == nil ? "" : " 이전 확인 값이에요.")) }
                if let data = metrics.snapshot {
                    if data.collectionPaused { notice("메트릭 수집이 일시 중지되어 있을 수 있어요 · 웹에서 확인해 주세요") }
                    if data.accounts.isEmpty { notice("등록된 채널이 없어요 · 웹에서 계정을 등록해 주세요") }
                    else {
                        // 네 채널은 2×2로 배치하고 창의 남은 높이를 모두 그래프에 할당한다.
                        GeometryReader { geometry in
                            let columns = data.accounts.count == 1 ? 1 : 2
                            let rows = (data.accounts.count + columns - 1) / columns
                            let height = max(0, (geometry.size.height - CGFloat(rows - 1) * 12) / CGFloat(rows))
                            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                                ForEach(0..<rows, id: \.self) { row in
                                    GridRow {
                                        ForEach(0..<columns, id: \.self) { column in
                                            let index = row * columns + column
                                            if index < data.accounts.count {
                                                CreatorChannelChart(account: data.accounts[index]).frame(maxWidth: .infinity).frame(height: height)
                                            } else { Color.clear }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Text("서버 수집 \(timestamp(data.updatedAt)) · 앱 조회 \(timestamp(metrics.lastCheckedAt))")
                        .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                } else if metrics.isRefreshing { ProgressView("프로필 메트릭을 확인하고 있어요").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if metrics.errorMessage == nil && !store.isOffline { notice("새로고침을 눌러 프로필 메트릭을 확인해 주세요") }
            }
            if metrics.snapshot == nil { Spacer(minLength: 0) }
            HStack {
                Text(refreshStatus).font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                Spacer()
                Button("웹에서 자세히 보기 ↗") { NSWorkspace.shared.open(Self.website) }.buttonStyle(.plain).font(.system(size: 12))
            }.padding(.top, 10).overlay(alignment: .top) { Rectangle().fill(BunnyTheme.border).frame(height: 1) }
        }.padding(18)
            .task(id: online ? store.snapshot?.workspaceKey : nil) { if online { await metrics.refreshWhileVisible() } }
            .task(id: online ? metrics.refreshDeadline : nil) { if online { await metrics.observeRefreshDeadline() } }
            .onDisappear { metrics.stop() }
    }
    private var refreshStatus: String {
        if store.isDemo || store.snapshot == nil { return "계정 연결 후 조회할 수 있어요" }
        if !online { return "온라인 상태에서 새로고침할 수 있어요" }
        if metrics.isRefreshing { return "ZCRE 서버에서 조회 중" }
        if metrics.retryDelay > 0 {
            return "\(Date.now.addingTimeInterval(metrics.retryDelay).formatted(date: .omitted, time: .standard)) 이후 다시 조회할 수 있어요"
        }
        return "탭을 보는 동안 10분마다 조회 · 수동 새로고침 가능"
    }
    private func timestamp(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "정보 없음"
    }
    private func load(manual: Bool = false) { if online { metrics.refresh(manual: manual) } }
    private func notice(_ value: String) -> some View { Text(value).font(.caption).foregroundStyle(BunnyTheme.muted) }
    private func count(_ value: Int64?) -> String { value?.formatted() ?? "—" }
    private func change(_ value: Int64?) -> String { value.map { ($0 > 0 ? "+" : "") + $0.formatted() } ?? "—" }
}

private struct CreatorChannelChart: View {
    let account: CreatorMetrics.Account
    private var points: [CreatorMetrics.Account.Day] { account.daily.filter { $0.followers != nil && $0.date != nil }.sorted { $0.day < $1.day } }
    private var axisDates: [Date] {
        let dates = points.compactMap(\.date)
        guard dates.count > 4 else { return dates }
        return [0, (dates.count - 1) / 3, 2 * (dates.count - 1) / 3, dates.count - 1].map { dates[$0] }
    }
    private var color: Color {
        switch account.platform { case "instagram": .pink; case "tiktok": .cyan; case "youtube": .red; default: .mint }
    }
    private var domain: ClosedRange<Double> {
        let values = points.compactMap(\.followers).map(Double.init)
        let low = values.min() ?? 0, high = values.max() ?? 1
        let padding = max(1, (high - low) * 0.18)
        return max(0, low - padding)...(high + padding)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(account.platformName).font(.system(size: 13, weight: .semibold))
                    }
                    Text(account.handle.hasPrefix("@") ? account.handle : "@" + account.handle)
                        .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(account.followers?.formatted() ?? "—").font(.system(size: 17, weight: .semibold)).monospacedDigit()
                    Text(account.platform == "youtube" ? "구독자" : "팔로워").font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                }
            }
            if points.isEmpty {
                Text(account.trendUnavailable ? "추이 조회 불가 · 잠시 후 다시 확인해 주세요" : "아직 수집된 추이 기록이 없어요")
                    .font(.caption).foregroundStyle(BunnyTheme.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(points, id: \.day) { point in
                    if let date = point.date, let followers = point.followers {
                        LineMark(x: .value("날짜", date), y: .value("팔로워", Double(followers)))
                            .interpolationMethod(.linear).foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("날짜", date), y: .value("팔로워", Double(followers)))
                            .foregroundStyle(color).symbolSize(20)
                    }
                }
                .chartYScale(domain: domain)
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in AxisGridLine().foregroundStyle(BunnyTheme.border); AxisValueLabel() } }
                .chartXAxis { AxisMarks(values: axisDates) { value in
                    AxisValueLabel { if let date = value.as(Date.self) { Text(dayLabel(date)) } }
                } }
                .font(.system(size: 9)).padding(.top, 2)
                .accessibilityLabel("\(account.platformName) 팔로워 추이, 수집 기록 \(points.count)개")
            }
        }.padding(13).background(BunnyTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "M/d"; formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
