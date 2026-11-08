import AVFoundation
import AppKit
import Testing
@testable import ZCREBunny

// 심사 데모가 외부 계정이나 네트워크 URL을 요구하지 않으며 실제 미디어를 포함하는지 검사한다.
@Test @MainActor func reviewSamplesAreLocalAndDecodable() async throws {
    for kind in DemoMedia.allCases {
        let url = try #require(kind.url)
        #expect(url.isFileURL)
        #expect(try Data(contentsOf: url).count > 0)
        if kind == .image { #expect(NSImage(contentsOf: url) != nil) }
        else {
            let duration = try await AVURLAsset(url: url).load(.duration)
            #expect(duration.seconds > 0)
        }
    }
}
