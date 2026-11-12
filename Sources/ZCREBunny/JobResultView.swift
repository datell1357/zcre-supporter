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
    @State private var downloadProgress = ResultTransferProgress(received: 0, expected: nil)
    @State private var savedFile: URL?
    @State private var downloadRevision = UUID()
    @State private var downloadTask: Task<Void, Never>?
    private var accountMatches: Bool { store.snapshot?.workspaceKey == workspace && !store.isDemo }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(job.workName).font(.title3.bold())
            Text("\(job.startTimeLabel) 시작 · 작업 완료").font(.caption).foregroundStyle(BunnyTheme.muted)
            if !accountMatches {
                Text("계정 연결이 변경됐어요. 현황판에서 다시 열어 주세요.")
                Spacer()
            } else if loading && outputs.isEmpty {
                ProgressView("결과 확인 중").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if outputs.indices.contains(selected) {
                    if outputs.count > 1 {
                        Picker("결과", selection: $selected) {
                            ForEach(outputs.indices, id: \.self) { index in Text("결과 \(index + 1)").tag(index) }
                        }.disabled(downloading)
                    }
                    ResultMediaView(output: outputs[selected]).id(outputs[selected].id + outputs[selected].url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("아직 결과를 불러오지 못했어요. 잠시 후 다시 확인하거나 웹에서 열어 주세요.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if loading { ProgressView("결과를 다시 확인하고 있어요").controlSize(.small) }
                if downloading {
                    HStack {
                        if let value = downloadProgress.fraction { ProgressView(value: value).frame(maxWidth: .infinity) }
                        else { ProgressView().controlSize(.small) }
                        Text(progressLabel).font(.caption).monospacedDigit()
                        Button("취소") { downloadTask?.cancel() }.buttonStyle(ZCREButtonStyle())
                    }
                }
                if let message { Text(message).font(.caption).foregroundStyle(BunnyTheme.muted) }
                if let savedFile { Button("저장 폴더 열기") { NSWorkspace.shared.activateFileViewerSelecting([savedFile]) }.buttonStyle(.plain).foregroundStyle(BunnyTheme.accent) }
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
                loading = true; message = nil
                defer { if !Task.isCancelled { loading = false } }
                guard accountMatches else { outputs = []; loading = false; return }
                do {
                    let received = try await store.webSession.outputs(for: job.id, workspace: workspace)
                    try Task.checkCancellation()
                    guard accountMatches else { return }
                    outputs = received
                    if !outputs.indices.contains(selected) { selected = 0 }
                } catch is CancellationError { return }
                catch { message = "결과 조회가 지연됐어요. 잠시 후 다시 확인해 주세요." }
                loading = false
            }
            .onChange(of: accountMatches) { _, matches in
                if !matches { outputs = []; savedFile = nil; downloadTask?.cancel() }
            }
            .onDisappear { downloadTask?.cancel() }
    }

    private var progressLabel: String {
        let received = ByteCountFormatter.string(fromByteCount: downloadProgress.received, countStyle: .file)
        guard let expected = downloadProgress.expected else { return received }
        return "\(received) / \(ByteCountFormatter.string(fromByteCount: expected, countStyle: .file))"
    }

    /// 선택한 주소가 만료됐을 때만 한 번 갱신하고, 완전한 파일만 사용자 경로로 교체한다.
    private func download() {
        guard accountMatches, outputs.indices.contains(selected), !downloading else { return }
        let output = outputs[selected]
        guard let initial = output.downloadURL else { return }
        downloading = true; message = nil; savedFile = nil
        downloadProgress = .init(received: 0, expected: nil)
        let revision = UUID(); downloadRevision = revision
        downloadTask = Task { @MainActor in
            defer { downloading = false }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "ZCRE-\(job.createdAt.formatted(.iso8601).replacingOccurrences(of: ":", with: "-"))-\(selected + 1).\(output.fileExtension)"
            guard await panel.begin() == .OK, let destination = panel.url, accountMatches, !Task.isCancelled else { return }
            let started = ProcessInfo.processInfo.systemUptime
            var outcome = DiagnosticOutcome.networkError
            var status: Int?
            defer { DiagnosticMetrics.shared.record(.resultDownload, started: started, outcome: outcome, status: status) }
            do {
                let temporary = try await ResultDownload.fetch(initial: initial, refreshedURL: {
                    let refreshed = try await store.webSession.outputs(for: job.id, workspace: workspace, forceRefresh: true)
                    guard accountMatches, let url = refreshed.first(where: { $0.id == output.id })?.downloadURL else { throw CancellationError() }
                    return url
                }, transfer: { url in
                    guard accountMatches else { throw CancellationError() }
                    return try await ResultTransfer(progress: { value in
                        Task { @MainActor in
                            if downloadRevision == revision && downloading { downloadProgress = value }
                        }
                    }).fetch(url)
                })
                defer { ResultTransfer.removeTemporary(temporary) }
                try Task.checkCancellation()
                guard accountMatches else { throw CancellationError() }
                let scoped = destination.startAccessingSecurityScopedResource()
                defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
                // 파일 복사는 큰 영상에서도 메인 액터를 막지 않는다.
                let saveTask = Task.detached(priority: .utility) { try ResultTransfer.save(temporary, to: destination) }
                try await withTaskCancellationHandler {
                    try Task.checkCancellation()
                    try await saveTask.value
                } onCancel: { saveTask.cancel() }
                savedFile = destination; message = "다운로드를 저장했어요"
                outcome = .success; status = 200
            } catch {
                outcome = DiagnosticOutcome.failure(error)
                if case ResultTransferError.http(let code) = error { status = code }
                message = Self.downloadMessage(error)
            }
        }
    }

    private static func downloadMessage(_ error: Error) -> String {
        if error is CancellationError || (error as NSError).code == NSURLErrorCancelled { return "다운로드를 취소했어요" }
        if case ResultTransferError.insufficientSpace = error { return "저장 공간이 부족해요. 여유 공간을 확보한 뒤 다시 시도해 주세요." }
        if case ResultTransferError.http(let code) = error {
            return [401, 403, 404, 410].contains(code) ? "결과 주소를 갱신해도 내려받지 못했어요. 웹에서 결과를 확인해 주세요." : "서버에서 다운로드를 처리하지 못했어요. 잠시 후 다시 시도해 주세요."
        }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            return ns.code == NSFileWriteOutOfSpaceError ? "저장 공간이 부족해요." : "파일을 저장하지 못했어요. 저장 위치의 권한과 여유 공간을 확인해 주세요."
        }
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorTimedOut { return "다운로드 응답이 지연됐어요. 연결을 확인한 뒤 다시 시도해 주세요." }
        return "다운로드하지 못했어요. 연결을 확인하거나 웹에서 결과를 열어 주세요."
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

// SwiftUI VideoPlayer의 런타임 의존성을 피하고 AppKit 재생 컨트롤을 사용한다.
struct NativeResultPlayer: NSViewRepresentable {
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
