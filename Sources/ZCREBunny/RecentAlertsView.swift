// 기능 분류: 읽음 상태와 개수 제한을 적용한 로컬 알림 목록
import SwiftUI

struct RecentAlertsView: View {
    var store: CompanionStore
    var maximumCount: Int?
    var title = "최근 알림"
    var showAll: (() -> Void)?
    var close: () -> Void = {}

    // 호출 화면이 지정한 개수까지만 보여 주며 원본 이력은 변경하지 않는다.
    private var visibleAlerts: [CompanionAlert] { Array(store.alerts.prefix(maximumCount ?? store.alerts.count)) }
    // 최근 보관 이력의 범위를 설명한다.
    private var storageNote: String {
        if store.isDemo { return "미리보기 기록 · 저장하지 않아요" }
        if store.snapshot == nil { return "연결 전 테스트 알림 · 이번 실행에만 표시해요" }
        if store.alertHistorySaveFailed { return "이 Mac에 저장하지 못했어요 · 현재 목록만 표시해요" }
        if let maximumCount, store.alerts.count > maximumCount { return "최신 \(maximumCount)개 표시 · 전체 목록은 상세 현황에서" }
        return "\(store.alerts.count)개 보관 · 이 Mac에 저장돼요"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                if !store.alerts.isEmpty {
                    Button("전체 지우기") { store.clearAlerts() }.buttonStyle(.plain)
                        .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                }
            }
            if store.alerts.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.snapshot == nil ? "작업 기록 연결 대기" : store.alertHistoryClearedThrough != nil ? "알림 기록을 지웠어요" : "표시할 작업 기록이 없어요")
                        .font(.system(size: 12, weight: .medium))
                    Text(store.snapshot == nil ? "계정 연결 후 최근 완료·실패 기록을 가져와요." : "새 작업 완료·실패와 크레딧 부족 알림이 여기에 표시돼요.")
                        .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(BunnyTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(visibleAlerts) { alert in
                        Button {
                            store.markAlertRead(alert.id)
                            if let job = store.job(for: alert), alert.kind == .completed, !store.isDemo {
                                store.showResult?(job)
                            } else {
                                CompanionStore.openWebsite(path: alert.kind.path)
                                close()
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: alert.kind.symbol)
                                    .foregroundStyle(alert.kind == .completed ? BunnyTheme.success : .orange)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(alert.title).font(.system(size: 12, weight: .medium))
                                    Text(alert.body).font(.system(size: 11)).foregroundStyle(BunnyTheme.muted)
                                        .lineLimit(2).multilineTextAlignment(.leading)
                                    if alert.source == .workHistory {
                                        Text("기존 기록 · 시작 \(alert.createdAt.formatted(date: .numeric, time: .shortened))")
                                            .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                                    } else {
                                        Text(alert.createdAt, style: .relative).font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                                    }
                                }
                                Spacer(minLength: 0)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                        }.buttonStyle(.plain)
                        if alert.id != visibleAlerts.last?.id { Divider() }
                    }
                }
                if store.alerts.count > visibleAlerts.count, let showAll {
                    Button("알림 전체 보기 · \(store.alerts.count)개", action: showAll)
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(BunnyTheme.accent)
                }
                Text(storageNote)
                    .font(.system(size: 9)).foregroundStyle(BunnyTheme.muted)
            }
        }
    }
}
