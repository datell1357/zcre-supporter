import XCTest
@testable import ZCREBunny

final class PetQuickMenuTests: XCTestCase {
    func testAllToolsStayOnOfficialHTTPSOrigin() {
        XCTAssertEqual(ZCREQuickTool.allCases.count, 16)
        for tool in ZCREQuickTool.allCases {
            XCTAssertEqual(tool.url.scheme, "https")
            if tool == .zcut {
                XCTAssertEqual(tool.url.host, "zcut.ai")
                XCTAssertEqual(tool.url.path, "/projects")
            } else {
                XCTAssertEqual(tool.url.host, "www.zcre.co.kr")
                XCTAssertTrue(tool.url.path.hasPrefix("/studio/"))
            }
        }
    }
    func testImageAndVideoToolsAreSeparated() {
        XCTAssertEqual(ZCREQuickTool.allCases.filter { $0.isImage }.count, 6)
        XCTAssertEqual(ZCREQuickTool.allCases.filter(\.isVideo).count, 5)
        XCTAssertTrue(ZCREQuickTool.videoUpscale.isVideo)
        XCTAssertTrue(ZCREQuickTool.videoReframe.isVideo)
        XCTAssertFalse(ZCREQuickTool.imageUpscale.isVideo)
    }
    func testDirectToolsUseOfficialPagesWithoutEnteringImageMenus() {
        XCTAssertEqual(ZCREQuickTool.jiujitsu.url.path, "/studio/jiujitsu")
        XCTAssertEqual(ZCREQuickTool.audio.url.path, "/studio/audio")
        XCTAssertEqual(ZCREQuickTool.canvas.url.path, "/studio/canvas")
        XCTAssertEqual(ZCREQuickTool.depth.url.path, "/studio/video-depth")
        XCTAssertEqual(ZCREQuickTool.videoReframe.url.path, "/studio/video-reframe")
        XCTAssertEqual(ZCREQuickTool.resize.url.path, "/studio/image")
        for tool in [ZCREQuickTool.jiujitsu, .audio, .depth, .canvas] {
            XCTAssertFalse(tool.isImage)
            XCTAssertFalse(tool.isVideo)
        }
    }
    func testVideoUpscaleUsesVideoMode() {
        let query = URLComponents(url: ZCREQuickTool.videoUpscale.url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertTrue(query?.contains(URLQueryItem(name: "media", value: "video")) == true)
        XCTAssertTrue(query?.contains(URLQueryItem(name: "tool", value: "upscale")) == true)
    }
    func testNoSignedReferencesOrUploadParametersInShortcuts() {
        for tool in ZCREQuickTool.allCases {
            let query = URLComponents(url: tool.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertTrue(query.allSatisfy { ["tool", "media"].contains($0.name) })
        }
    }
}
