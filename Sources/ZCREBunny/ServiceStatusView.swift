// 기능 분류: 공개 서비스 상태 표시 · 오래된 정보 구분
import SwiftUI
import ZCRECore

struct ServiceStatusView: View {
    var status: ServiceStatusStore

    // 표시 시각의 로컬 갱신과 실제 HTTP 조회 주기는 별개다. HTTP 조회 수명은 ServiceStatusStore가 관리한다.
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("서비스 상태").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if status.isRefreshing { ProgressView().controlSize(.mini) }
                    Button { status.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).disabled(status.isRefreshing)
                        .accessibilityLabel("서비스 상태 새로고침")
                }
                if let snapshot = status.snapshot {
                    if status.isUnavailable {
                        Label(status.hasError ? "조회 지연 · 상태를 다시 확인 중이에요" : "집계 지연 · 상태를 다시 확인 중이에요", systemImage: "clock")
                            .font(.system(size: 10)).foregroundStyle(.orange)
                    } else {
                        Text(summary(snapshot)).font(.system(size: 11)).foregroundStyle(BunnyTheme.muted)
                    }
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(snapshot.models) { model in
                                serviceRow(model)
                            }
                        }
                    }
                } else {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: status.hasError ? "wifi.exclamationmark" : "network")
                            .font(.system(size: 24)).foregroundStyle(BunnyTheme.muted)
                        Text(status.hasError ? "서비스 상태를 불러오지 못했어요" : "서비스 상태를 확인하고 있어요")
                            .font(.system(size: 12))
                        if status.hasError {
                            Button("다시 확인") { status.refresh() }.buttonStyle(ZCREButtonStyle())
                        }
                    }.frame(maxWidth: .infinity)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let date = status.snapshot?.calculatedAt {
                        Text("집계 \(Self.timestamp(date)) KST · 1분마다 갱신")
                            .font(.system(size: 9)).foregroundStyle(BunnyTheme.muted)
                    } else {
                        Text("현황판을 열어두면 1분마다 갱신돼요")
                            .font(.system(size: 9)).foregroundStyle(BunnyTheme.muted)
                    }
                    Button("ZCRE 상태 페이지 ↗") { CompanionStore.openWebsite(path: "/status") }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                }.padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Rectangle().fill(BunnyTheme.border).frame(height: 1) }
            }.padding(.horizontal, 18).padding(.bottom, 16)
        }
    }
    /// 서비스별 상태와 모델 변형의 상태를 한 행에 표시한다.
    private func serviceRow(_ model: ServiceStatusSnapshot.Model) -> some View {
        let health = status.health(for: model)
        return HStack(spacing: 9) {
            Circle().fill(color(health)).frame(width: 6, height: 6)
            Text(model.label).font(.system(size: 12, weight: .medium)).lineLimit(1)
            Spacer(minLength: 4)
            Text(health.label).font(.system(size: 10, weight: .medium))
                .foregroundStyle(color(health)).fixedSize()
        }.padding(.horizontal, 11).padding(.vertical, 10)
            .background(BunnyTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
            .help(status.isUnavailable ? "최신 상태를 확인할 수 없어요. 잠시 후 다시 조회해요." : model.series.map { "\($0.label): \($0.health.label)" }.joined(separator: " · "))
    }
    /// 현재 공개 스냅샷의 정상·장애·확인 중 모델 수를 요약한다.
    private func summary(_ snapshot: ServiceStatusSnapshot) -> String {
        ServiceHealth.allCases.compactMap { health in
            let count = snapshot.models.filter { status.health(for: $0) == health }.count
            return count > 0 ? "\(health.label) \(count)개" : nil
        }.joined(separator: " · ")
    }
    /// 서비스 상태를 공통 색상으로 매핑한다.
    private func color(_ health: ServiceHealth) -> Color {
        switch health {
        case .operational: BunnyTheme.success
        case .delayed: .orange
        case .degraded: .red
        case .checking: BunnyTheme.muted
        }
    }
    /// 서비스 집계 시각을 한국 시간으로 표시한다.
    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "MM.dd HH:mm"
        return formatter.string(from: date)
    }
}
