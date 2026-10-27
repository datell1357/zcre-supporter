// 기능 분류: 선택한 결과 미리보기 · 명시적 재생 · 사용자 지정 위치로 다운로드
import SwiftUI
import AVKit
import ImageIO
import ZCRECore

struct JobResultView: View {
    var store: CompanionStore
    let job: GenerationJob
    let workspace: String
    @State private var outputs: [JobOutput] = []
    @State private var selected = 0
    @State private var loading = true
    @State private var message: String?
    @State private var reload = 0
    @State private var downloading = false
    @State private var downloadTask: Task<Void, Never>?
    private var accountMatches: Bool { store.snapshot?.workspaceKey == workspace && !store.isDemo }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(job.workName).font(.title3.bold())
            Text("\(job.startTimeLabel) 시작 · 작업 완료").font(.caption).foregroundStyle(BunnyTheme.muted)
            if !accountMatches {
                Text("계정 연결이 변경됐어요. 현황판에서 다시 열어 주세요.")
                Spacer()
            } else if loading {
                ProgressView("결과 확인 중").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if outputs.indices.contains(selected) {
                    if outputs.count > 1 {
                        Picker("결과", selection: $selected) {
                            ForEach(outputs.indices, id: \.self) { index in Text("결과 \(index + 1)").tag(index) }
                        }
                    }
                    ResultMediaView(output: outputs[selected]).id(outputs[selected].id + outputs[selected].url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("아직 결과를 불러오지 못했어요. 잠시 후 다시 확인하거나 웹에서 열어 주세요.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let message { Text(message).font(.caption).foregroundStyle(BunnyTheme.muted) }
                HStack {
                    Button("결과 열기 ↗") { NSWorkspace.shared.open(JobResultLink.url(for: job)) }
                    Button("다시 확인") { reload += 1 }.disabled(downloading)
                    Spacer()
                    Button(downloading ? "다운로드 중…" : "다운로드") { download() }
                        .disabled(downloading || !outputs.indices.contains(selected))
                }.buttonStyle(ZCREButtonStyle())
                Text("영상·오디오는 재생을 눌렀을 때만 불러와요 · 원본은 다운로드할 때만 저장돼요")
                    .font(.system(size: 10)).foregroundStyle(BunnyTheme.muted)
            }
        }.padding(22).frame(width: 600, height: 660)
            .background(BunnyTheme.background).foregroundStyle(BunnyTheme.foreground).preferredColorScheme(.dark)
            .task(id: "\(store.snapshot?.workspaceKey ?? "none"):\(reload)") {
                outputs = []; selected = 0; loading = true; message = nil
                guard accountMatches else { loading = false; return }
                do {
                    let received = try await store.webSession.outputs(for: job.id, workspace: workspace)
                    try Task.checkCancellation()
                    guard accountMatches else { return }
                    outputs = received
                } catch is CancellationError { return }
                catch { message = "결과 조회가 지연됐어요. 잠시 후 다시 확인해 주세요." }
                loading = false
            }
            .onChange(of: accountMatches) { _, matches in if !matches { downloadTask?.cancel() } }
            .onDisappear { downloadTask?.cancel() }
    }

    /// 다운로드 직전에 만료된 주소를 갱신하고 파일 스트리밍으로 메모리 사용을 제한한다.
    private func download() {
        guard accountMatches, outputs.indices.contains(selected), !downloading else { return }
        let output = outputs[selected]
        downloading = true; message = nil
        downloadTask = Task { @MainActor in
            defer { downloading = false }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "ZCRE-\(job.createdAt.formatted(.iso8601).replacingOccurrences(of: ":", with: "-"))-\(selected + 1).\(output.fileExtension)"
            guard await panel.begin() == .OK, let destination = panel.url, accountMatches, !Task.isCancelled else { return }
            do {
                let refreshed = try await store.webSession.outputs(for: job.id, workspace: workspace)
                guard accountMatches, let url = refreshed.first(where: { $0.id == output.id })?.downloadURL else { throw SnapshotError.invalidResponse }
                let session = URLSession(configuration: .ephemeral)
                defer { session.invalidateAndCancel() }
                let (temporary, response) = try await session.download(from: url)
                defer { try? FileManager.default.removeItem(at: temporary) }
                try Task.checkCancellation()
                guard accountMatches, (response as? HTTPURLResponse)?.statusCode == 200 else { throw SnapshotError.network }
                if FileManager.default.fileExists(atPath: destination.path) {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
                } else { try FileManager.default.copyItem(at: temporary, to: destination) }
                message = "다운로드를 저장했어요"
            } catch is CancellationError { }
            catch { message = "다운로드하지 못했어요. 결과 열기에서 확인하거나 다시 시도해 주세요." }
        }
    }
}

private struct ResultMediaView: View {
    let output: JobOutput
    @State private var image: NSImage?
    @State private var player: AVPlayer?
    @State private var message: String?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(BunnyTheme.surface)
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(8)
            } else if let player {
                NativeResultPlayer(player: player).padding(8)
            } else if output.kind == "video" || output.kind == "audio" {
                Button {
                    guard let url = output.previewURL else { return }
                    let p = AVPlayer(url: url)
                    p.automaticallyWaitsToMinimizeStalling = true
                    player = p; p.play()
                } label: { Label(output.kind == "video" ? "영상 미리보기 재생" : "오디오 재생", systemImage: "play.circle.fill").font(.title3) }
                    .buttonStyle(.plain)
            } else if let message {
                Text(message).font(.callout).padding(20)
            } else { ProgressView("이미지 불러오는 중") }
        }.task(id: output.url) {
            guard output.kind == "image", let url = output.previewURL else { return }
            do { image = try await ResultImageCache.load(url) }
            catch is CancellationError { }
            catch { message = "미리보기 용량이 크거나 불러올 수 없어요. 결과 열기 또는 다운로드를 이용해 주세요." }
        }.onDisappear { player?.pause(); player?.replaceCurrentItem(with: nil); player = nil }
    }
}

@MainActor enum ResultImageCache {
    // 서명 URL과 디코딩 이미지는 메모리에만 보관하며 최대 24MB·12개로 제한한다.
    static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>(); cache.totalCostLimit = 24 * 1024 * 1024; cache.countLimit = 12; return cache
    }()
    static func load(_ url: URL) async throws -> NSImage {
        if let image = cache.object(forKey: url as NSURL) { return image }
        let thumbnail = try await fetchThumbnail(url)
        try Task.checkCancellation()
        let image = NSImage(cgImage: thumbnail, size: .zero)
        cache.setObject(image, forKey: url as NSURL, cost: thumbnail.bytesPerRow * thumbnail.height)
        return image
    }
    // 전송 바이트 제한과 이미지 축소는 메인 액터 밖에서 실행한다.
    nonisolated static func fetchThumbnail(_ url: URL) async throws -> CGImage {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, response.expectedContentLength <= 12 * 1024 * 1024 else { throw SnapshotError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            if data.count % 65536 == 0 { try Task.checkCancellation() }
            guard data.count < 12 * 1024 * 1024 else { throw SnapshotError.invalidResponse }
            data.append(byte)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1100, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw SnapshotError.invalidResponse }
        return thumbnail
    }
}

// SwiftUI VideoPlayer의 런타임 의존성을 피하고 AppKit 재생 컨트롤을 사용한다.
private struct NativeResultPlayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = player
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause(); view.player = nil
    }
}
