import AppKit
import Foundation

// 기능 분류: 번들 지크 이미지로 macOS 앱 아이콘을 만든다. 외부 이미지를 다운로드하지 않는다.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let mascotURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/ZCREBunny/Resources/Zic/still.png")
guard let mascot = NSImage(contentsOf: mascotURL) else { fatalError("Missing Zic icon artwork") }
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
// macOS가 요구하는 각 논리 크기에 1배·2배 해상도 이미지를 저장한다.
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 512); transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 24, y: 24, width: 464, height: 464), xRadius: 104, yRadius: 104)
        NSColor(srgbRed: 7 / 255, green: 10 / 255, blue: 15 / 255, alpha: 1).setFill()
        background.fill()
        NSColor(srgbRed: 36 / 255, green: 39 / 255, blue: 42 / 255, alpha: 1).setStroke()
        background.lineWidth = 2; background.stroke()
        mascot.draw(in: NSRect(x: 26, y: 26, width: 460, height: 460), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
