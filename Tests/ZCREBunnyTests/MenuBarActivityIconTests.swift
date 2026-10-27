// 검증 분류: 로컬 데이터와 번들 리소스 기반 회귀 테스트. 실제 생성·결제 요청은 보내지 않는다.
import AppKit
import Testing
@testable import ZCREBunny

// 실제 작업 중이고 깨어 있을 때만 메뉴 지크가 달리는지 검증한다.
@Test @MainActor func menuRabbitRunsOnlyForActiveAwakeWork() {
    let button = NSButton()
    let icon = MenuBarActivityIcon(button: button)
    icon.update(activeJobs: 0, sleeping: false, reduceMotion: false)
    #expect(!icon.isAnimating)
    icon.update(activeJobs: 2, sleeping: false, reduceMotion: false)
    #expect(icon.isAnimating)
    icon.update(activeJobs: 1, sleeping: true, reduceMotion: false)
    #expect(!icon.isAnimating)
    icon.update(activeJobs: 1, sleeping: false, reduceMotion: true)
    #expect(!icon.isAnimating)
    icon.update(activeJobs: 1, sleeping: false, reduceMotion: false)
    #expect(icon.isAnimating)
    icon.update(activeJobs: 0, sleeping: false, reduceMotion: false)
    #expect(!icon.isAnimating)
    #expect(button.image != nil)
}

// 달리기 프레임의 자세 차이와 고정 메뉴 폭을 검증한다.
@Test @MainActor func runningFramesHaveDistinctPosesAndStableMenuWidth() throws {
    let frames = MenuBarActivityIcon.frames
    #expect(frames.count == 12)
    #expect(frames.allSatisfy { !$0.isTemplate && $0.size == MenuBarActivityIcon.iconSize })
    let rendered = frames.compactMap(\.tiffRepresentation)
    #expect(rendered.count == frames.count)
    #expect(Set(rendered).count >= 4)
    // Optional offline contact sheet; never displays a window or starts a job.
    if let path = ProcessInfo.processInfo.environment["ZCRE_MENU_PREVIEW"] {
        let sheet = NSImage(size: NSSize(width: 720, height: 224))
        sheet.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 112, width: 720, height: 112).fill()
        NSColor(calibratedWhite: 0.07, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 720, height: 112).fill()
        for (index, frame) in frames.enumerated() {
            for y: CGFloat in [16, 128] {
                frame.draw(in: NSRect(x: CGFloat(index) * 60, y: y, width: 56, height: 40))
                frame.draw(in: NSRect(x: CGFloat(index) * 60 + 14, y: y + 58, width: 28, height: 20))
            }
        }
        sheet.unlockFocus()
        let bitmap = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
}

// 작업 테스트가 계정 작업을 만들지 않고 메뉴 애니메이션만 재생하는지 검증한다.
@Test @MainActor func workPreviewAnimatesWithoutInventingAccountJobs() {
    let button = NSButton()
    let icon = MenuBarActivityIcon(button: button)
    icon.update(activeJobs: 0, previewWorking: true, sleeping: false, reduceMotion: false)
    #expect(icon.isAnimating)
    icon.update(activeJobs: 0, previewWorking: false, sleeping: false, reduceMotion: false)
    #expect(!icon.isAnimating)
    icon.update(activeJobs: 2, previewWorking: false, sleeping: false, reduceMotion: false)
    #expect(icon.isAnimating)
    icon.update(activeJobs: 0, previewWorking: true, sleeping: true, reduceMotion: false)
    #expect(!icon.isAnimating)
}
