import XCTest
@testable import ZCREBunny

@MainActor
final class ZCREWorkspaceTests: XCTestCase {
    func testSignedAttachmentURLsUseMacSavePanel() {
        let url = URL(string: "https://example.s3.ap-northeast-2.amazonaws.com/result.mp4?response-content-disposition=attachment")!
        XCTAssertTrue(ZCREWorkspaceController.isDownloadURL(url))
    }

    func testZCUTCloudVideoUsesDownloadFlow() {
        let url = URL(string: "https://zcut-prd-projects.s3.ap-northeast-2.amazonaws.com/project/result.mp4?signed=yes")!
        XCTAssertTrue(ZCREWorkspaceController.isDownloadURL(url))
    }

    func testRegularWebPageRemainsInsideTheEditor() {
        XCTAssertFalse(ZCREWorkspaceController.isDownloadURL(URL(string: "https://zcut.ai/editor/project")!))
    }

    /// 모든 원형 메뉴 도구는 작업 창에서 시작할 수 있는 공식 주소여야 한다.
    func testEveryQuickToolOpensInsideTheWorkspace() {
        for tool in ZCREQuickTool.allCases {
            XCTAssertTrue(ZCREWorkspaceController.isAllowedStart(tool.url), tool.rawValue)
            XCTAssertEqual(ZCREQuickTool.matching(tool.url), tool, tool.rawValue)
        }
        XCTAssertFalse(ZCREWorkspaceController.isAllowedStart(URL(string: "http://www.zcre.co.kr/studio/image")!))
        XCTAssertFalse(ZCREWorkspaceController.isAllowedStart(URL(string: "https://zcre.co.kr.example.com/")!))
    }

    /// 웹 안에서 쿼리만 바뀐 도구 이동도 정확한 도구로 인식한다.
    func testWebNavigationFollowsTheMatchingTool() {
        XCTAssertEqual(ZCREQuickTool.matching(URL(string: "https://www.zcre.co.kr/studio/image?tool=upscale&media=video&x=1")!), .videoUpscale)
        XCTAssertEqual(ZCREQuickTool.matching(URL(string: "https://www.zcre.co.kr/studio/image?tool=upscale")!), .imageUpscale)
        XCTAssertEqual(ZCREQuickTool.matching(URL(string: "https://zcut.ai/projects/abc")!), .zcut)
        XCTAssertEqual(ZCREQuickTool.matching(URL(string: "https://zcut.ai/editor/project-id")!), .zcut)
        XCTAssertEqual(ZCREQuickTool.matching(URL(string: "https://www.zcre.co.kr/studio/video-reframe")!), .videoReframe)
        XCTAssertNil(ZCREQuickTool.matching(URL(string: "https://www.zcre.co.kr/history")!))
    }

    /// 도구 메뉴 분류에 원형 메뉴의 도구가 빠짐없이 들어 있다.
    func testToolMenuGroupsCoverQuickMenuTools() {
        let grouped = Set(ZCREQuickTool.groups.flatMap(\.tools))
        XCTAssertEqual(grouped, Set(ZCREQuickTool.allCases))
    }
}
