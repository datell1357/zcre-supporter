import XCTest
import ZCRECore
@testable import ZCREBunny

final class JobOutputsTests: XCTestCase {
    func testRejectsUnsafeResultURLs() {
        for value in ["http://example.com/a", "file:///tmp/a", "javascript:alert(1)", "https://user:password@example.com/a", "https://localhost/a", "https://127.0.0.1/a", "https://[::1]/a"] {
            XCTAssertNil(JobOutput.safeURL(value), value)
        }
        XCTAssertNotNil(JobOutput.safeURL("https://cdn.example.com/output.mp4?signature=sample"))
    }
    func testMetadataAndOriginalDownload() throws {
        let payload = try JSONDecoder().decode(JobOutputsPayload.self, from: Data(#"{"outputs":[{"id":"one","mediaType":"video","contentType":"video/mp4","url":"https://cdn.example.com/preview.mp4","originalURL":"https://cdn.example.com/original.mp4","expires":60}]}"#.utf8))
        let output = try XCTUnwrap(payload.outputs?.first)
        XCTAssertEqual(output.kind, "video")
        XCTAssertEqual(output.fileExtension, "mp4")
        XCTAssertEqual(output.downloadURL?.lastPathComponent, "original.mp4")
    }
    func testSafeFallbackWhenOriginalIsUnsafe() throws {
        let output = try JSONDecoder().decode(JobOutput.self, from: Data(#"{"id":"one","url":"https://cdn.example.com/a","originalURL":"file:///tmp/a","contentType":"image/png"}"#.utf8))
        XCTAssertEqual(output.downloadURL, output.previewURL)
        XCTAssertEqual(output.kind, "image")
    }
    func testExactJobLinks() {
        let image = GenerationJob(id: "req_example", model: "test", mediaType: "image", status: .succeeded, createdAt: .now)
        let audio = GenerationJob(id: "req_example", model: "test", mediaType: "audio", status: .succeeded, createdAt: .now)
        XCTAssertEqual(JobResultLink.url(for: image).absoluteString, "https://www.zcre.co.kr/results/req_example")
        XCTAssertEqual(JobResultLink.url(for: audio).absoluteString, "https://www.zcre.co.kr/studio/audio?j=req_example")
    }
}
