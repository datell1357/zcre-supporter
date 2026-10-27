import XCTest
@testable import ZCREBunny

final class PetQuickMenuTests: XCTestCase {
    func testAllToolsStayOnOfficialHTTPSOrigin() {
        XCTAssertEqual(ZCREQuickTool.allCases.count, 12)
        for tool in ZCREQuickTool.allCases {
            XCTAssertEqual(tool.url.scheme, "https")
            XCTAssertEqual(tool.url.host, "www.zcre.co.kr")
            XCTAssertTrue(tool.url.path.hasPrefix("/studio/"))
        }
    }
    func testImageAndVideoToolsAreSeparated() {
        XCTAssertEqual(ZCREQuickTool.allCases.filter { $0.isImage }.count, 6)
        XCTAssertEqual(ZCREQuickTool.allCases.filter(\.isVideo).count, 4)
        XCTAssertTrue(ZCREQuickTool.videoUpscale.isVideo)
        XCTAssertFalse(ZCREQuickTool.imageUpscale.isVideo)
    }
    func testDirectToolsUseOfficialPagesWithoutEnteringImageMenus() {
        XCTAssertEqual(ZCREQuickTool.jiujitsu.url.path, "/studio/jiujitsu")
        XCTAssertEqual(ZCREQuickTool.audio.url.path, "/studio/audio")
        for tool in [ZCREQuickTool.jiujitsu, .audio] {
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
