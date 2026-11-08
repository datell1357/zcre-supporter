// 기능 분류: 로그인 없이 체험하는 번들 샘플 재생·저장. 실제 계정 결과 조회와 분리한다.
import SwiftUI
import AVKit

enum DemoMedia: String, CaseIterable, Identifiable {
    case image = "이미지", video = "영상", audio = "오디오"
    var id: String { rawValue }
    var url: URL? {
        switch self {
        case .image: Bundle.module.url(forResource: "still", withExtension: "png", subdirectory: "Zic")
        case .video: Bundle.module.url(forResource: "sample", withExtension: "mp4", subdirectory: "ReviewDemo")
        case .audio: Bundle.module.url(forResource: "grab", withExtension: "wav", subdirectory: "Sounds")
        }
    }
}

struct DemoResultView: View {
    @Bindable var store: CompanionStore
    @State private var media: DemoMedia = .video
    @State private var player: AVPlayer?
    @State private var message: String?
    private var available: Bool { store.isDemo && store.snapshot?.workspaceKey == "demo" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("미리보기 · 결과 재생과 저장").font(.title3.bold())
            Text("앱에 포함된 샘플이에요. 실제 생성 결과가 아니며 크레딧을 사용하지 않아요.")
                .font(.caption).foregroundStyle(BunnyTheme.muted)
            if available {
                Picker("샘플 종류", selection: $media) {
                    ForEach(DemoMedia.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(BunnyTheme.surface)
                    if let url = media.url {
                        if media == .image, let image = NSImage(contentsOf: url) {
                            Image(nsImage: image).resizable().scaledToFit().padding(12)
                        } else if let player {
                            NativeResultPlayer(player: player).padding(8)
                        } else {
                            Button("\(media.rawValue) 샘플 재생", systemImage: "play.circle.fill") {
                                let sample = AVPlayer(url: url); player = sample; sample.play()
                            }.buttonStyle(ZCREButtonStyle())
                        }
                    } else { Text("샘플 파일을 불러오지 못했어요") }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if let message { Text(message).font(.caption).foregroundStyle(BunnyTheme.muted) }
                Button("샘플 다운로드") { Task { await save() } }
                    .buttonStyle(ZCREButtonStyle()).disabled(media.url == nil)
            } else {
                Text("미리보기 모드가 종료됐어요. 창을 닫고 현황판에서 다시 열어 주세요.")
                Spacer()
            }
        }.padding(22).frame(width: 600, height: 660)
            .background(BunnyTheme.background).foregroundStyle(BunnyTheme.foreground).preferredColorScheme(.dark)
            .onChange(of: media) { _, _ in stop(); message = nil }
            .onChange(of: available) { _, _ in stop() }
            .onDisappear { stop() }
    }

    private func stop() { player?.pause(); player?.replaceCurrentItem(with: nil); player = nil }

    /// 선택한 로컬 번들 샘플만 사용자 지정 위치에 복사한다. 네트워크·계정 데이터는 사용하지 않는다.
    @MainActor private func save() async {
        guard available, let source = media.url else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ZCRE-demo.\(source.pathExtension)"
        guard await panel.begin() == .OK, let destination = panel.url, available else { return }
        let access = destination.startAccessingSecurityScopedResource()
        defer { if access { destination.stopAccessingSecurityScopedResource() } }
        do {
            try Data(contentsOf: source).write(to: destination, options: .atomic)
            message = "샘플을 저장했어요"
        } catch { message = "저장하지 못했어요. 다른 위치를 선택해 주세요." }
    }
}
