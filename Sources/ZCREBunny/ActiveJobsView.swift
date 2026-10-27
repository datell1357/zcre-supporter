// 기능 분류: 기존 스냅샷만 사용하는 진행 중 작업 패널. 별도 조회·타이머 없음.
import SwiftUI
import ZCRECore

struct ActiveJobsView: View {
    var store: CompanionStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("진행 중 작업").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(store.snapshot == nil ? "—" : "\(store.activeJobs.count)개").foregroundStyle(BunnyTheme.muted)
            }
            if store.isStale {
                Text("갱신 지연 · 마지막 확인 상태예요").font(.caption).foregroundStyle(.orange)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if store.activeJobs.isEmpty {
                        Label(store.snapshot == nil ? "계정 연결 대기" : "진행 중인 작업이 없어요", systemImage: "checkmark.circle")
                            .font(.system(size: 12)).foregroundStyle(BunnyTheme.muted).padding(.vertical, 20)
                    }
                    ForEach(store.activeJobs) { job in
                        Button { NSWorkspace.shared.open(JobResultLink.url(for: job)) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(job.workName, systemImage: job.symbol)
                                    .font(.system(size: 13, weight: .semibold)).lineLimit(2)
                                HStack {
                                    Text(job.status.label).foregroundStyle(BunnyTheme.accent)
                                    Spacer()
                                    Text(job.startTimeLabel + " 시작")
                                }.font(.system(size: 11))
                                HStack(spacing: 4) {
                                    Text("경과")
                                    Text(job.createdAt, style: .relative).monospacedDigit()
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }.font(.system(size: 11)).foregroundStyle(BunnyTheme.muted)
                            }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                                .background(BunnyTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).disabled(store.isDemo)
                    }
                }
            }
            Text("기존 작업 조회와 함께 갱신돼요")
                .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
        }.padding(18)
    }
}
