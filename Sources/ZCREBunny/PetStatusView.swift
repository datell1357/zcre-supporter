// 기능 분류: 지크 클릭 시 크레딧과 동시 생성 사용량 요약
import SwiftUI
import ZCRECore

struct PetStatusView: View {
    static let preferredSize = CGSize(width: 232, height: 104)
    var store: CompanionStore
    var showSettings: () -> Void
    var size = preferredSize
    var showsSettings = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(store.creditText).help(store.snapshot.map { "크레딧 확인: \($0.balanceFetchedAt.formatted(date: .omitted, time: .standard))" } ?? "연결 대기").font(.system(size: 22, weight: .semibold)).monospacedDigit()
                Text(store.isDemo ? "Credit · 미리보기" : (store.snapshot?.balanceIsStale == true ? "Credit · 갱신 지연" : "Credit")).font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
                Spacer()
                if showsSettings {
                    Button(action: showSettings) { Image(systemName: "slider.horizontal.3") }
                        .buttonStyle(.plain).foregroundStyle(BunnyTheme.muted).accessibilityLabel("지크 설정")
                }
            }.accessibilityElement(children: .contain)
            if store.snapshot == nil {
                Button("ZCRE 연결") { store.connect() }.buttonStyle(ZCREButtonStyle())
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("동시 생성 한도").font(.system(size: 11, weight: .medium))
                        Spacer()
                        if store.isStale { Image(systemName: "clock").help(store.delayMessage) }
                    }
                    let usage = store.snapshot?.concurrency
                    HStack(spacing: 10) {
                        counter("photo", title: "이미지", active: usage?.imagesActive ?? store.activeJobs.filter { $0.mediaType == "image" }.count, limit: usage?.imagesLimit)
                        counter("video", title: "영상", active: usage?.videosActive ?? store.activeJobs.filter { $0.mediaType == "video" }.count, limit: usage?.videosLimit)
                        Spacer(minLength: 0)
                        Text("합산 \(count(usage?.totalActive ?? store.activeJobs.count, usage?.totalLimit))")
                            .accessibilityLabel("전체 \(count(usage?.totalActive ?? store.activeJobs.count, usage?.totalLimit)) 진행 중")
                    }.font(.system(size: 11)).foregroundStyle(BunnyTheme.muted).monospacedDigit()
                }
            }
        }.padding(12).frame(width: size.width, height: size.height)
            .background(BunnyTheme.background).foregroundStyle(BunnyTheme.foreground).preferredColorScheme(.dark)
    }
    /// 한도를 알 수 없으면 임의 값을 만들지 않고 사용 개수만 표시한다.
    private func count(_ active: Int, _ limit: Int?) -> String {
        limit.map { "\(active)/\($0)" } ?? "\(active)"
    }
    /// 이미지·영상별 사용량과 한도를 아이콘 및 접근성 설명으로 표시한다.
    private func counter(_ symbol: String, title: String, active: Int, limit: Int?) -> some View {
        HStack(spacing: 4) { Image(systemName: symbol); Text(count(active, limit)) }
            .accessibilityElement(children: .ignore).accessibilityLabel("\(title) \(count(active, limit)) 진행 중")
    }
}
