// 기능 분류: 메뉴 막대 지크 애니메이션 · 로컬 이미지 캐시
import AppKit

/// 작업 중에만 타이머를 사용하고 캐시한 캐릭터 프레임으로
/// 승인된 달리기 모션을 표시해 SwiftUI 화면을 반복 렌더링하지 않는다.
@MainActor
final class MenuBarActivityIcon {
    private weak var button: NSButton?
    private var timer: Timer?
    private(set) var frameIndex = 0
    var isAnimating: Bool { timer != nil }
    static let iconSize = NSSize(width: 28, height: 20)
    private let idle = MenuBarActivityIcon.render(ZicSprites.shared.clip(.idle).frames[0])
    private static let run = ZicSprites.shared.clip(.run)
    // 원래 네 발을 가진 실제 전력 질주 클립에서 프레임을 추출한다.
    static let frames = (0..<12).map { index in
        render(run.frames[index * run.frames.count / 12])
    }
    private static let frameInterval = max(1.0 / 24, run.duration / Double(frames.count))

    /// 메뉴 막대 버튼에 기본 정지 이미지를 설정한다.
    init(button: NSButton) { self.button = button; button.image = idle }

    /// 작업 중이거나 작업 테스트 중일 때만 달리기를 켜며 잠자기와 동작 줄이기 설정을 따른다.
    func update(activeJobs: Int, previewWorking: Bool = false, sleeping: Bool, reduceMotion: Bool) {
        let working = activeJobs > 0 || previewWorking
        let shouldAnimate = working && !sleeping && !reduceMotion
        if shouldAnimate {
            guard timer == nil else { return }
            frameIndex = 0
            button?.image = Self.frames[frameIndex]
            let timer = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.advance() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate(); timer = nil; frameIndex = 0
            button?.image = working ? Self.frames[0] : idle
        }
    }

    /// 미리 그린 프레임을 순환해 버튼 이미지 하나만 바꾼다.
    private func advance() {
        frameIndex = (frameIndex + 1) % Self.frames.count
        button?.image = Self.frames[frameIndex]
    }

    /// 스프라이트 비율과 메뉴 폭을 유지하는 Retina용 메뉴 이미지를 만든다.
    private static func render(_ source: NSImage) -> NSImage {
        // 작은 Retina 이미지를 한 번 캐시한다. 대기·작업 아이콘 모두
        // 같은 캔버스와 캐릭터의 색·윤곽·신체 형태를 유지한다.
        let scale: CGFloat = 2
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(iconSize.width * scale), pixelsHigh: Int(iconSize.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        context.imageInterpolation = .high
        let factor = min((iconSize.width - 2) / source.size.width, (iconSize.height - 1) / source.size.height)
        let size = NSSize(width: source.size.width * factor, height: source.size.height * factor)
        source.draw(in: NSRect(x: (iconSize.width - size.width) / 2, y: 0.5, width: size.width, height: size.height),
                    from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        bitmap.size = iconSize
        let image = NSImage(size: iconSize)
        image.addRepresentation(bitmap)
        image.isTemplate = false
        image.accessibilityDescription = AppInfo.name
        return image
    }
}
