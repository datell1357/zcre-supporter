// 기능 분류: 스프라이트 리소스 검증 · 프레임 캐시 · 모션 우선순위
import AppKit
import SwiftUI
import ZCRECore

enum ZicMotion: String, CaseIterable {
    case idle, walk, drag, complete, run, working, cry, wave
    case walkFront = "walk-front", walkBack = "walk-back", walkSide = "walk-side", walkBackDiagonal = "walk-back-diagonal"
    /// 이동 방향에 맞는 정면·측면·후면 걷기 클립을 선택한다.
    static func walking(_ direction: WalkDirection) -> Self {
        switch direction {
        case .north: .walkBack
        case .south: .walkFront
        case .east, .west: .walkSide
        case .northEast, .northWest: .walkBackDiagonal
        case .southEast, .southWest: .walk
        }
    }
    var isWalking: Bool { rawValue.hasPrefix("walk") }

    /// 테스트·드래그·실패/완료 반응을 작업 중·산책보다 우선한다.
    static func resolve(test: Self?, dragging: Bool, celebrating: Bool, working: Bool, moving: Bool, direction: WalkDirection, failing: Bool = false, waving: Bool = false) -> Self {
        if let test { return test }
        if dragging { return .drag }
        if failing { return .cry }
        if celebrating { return .complete }
        if working { return .working }
        if moving { return .walking(direction) }
        return waving ? .wave : .idle
    }
}

struct SpriteMetadata: Decodable {
    let frames: Int
    let w: Int
    let h: Int
    let body_h: Double
    let anchor: [Double]?
    let grab_anchor: [Double]?
    let grab_anchors: [[Double]]?
    let grab_scales: [Double]?
    let grab_rotation_degrees: Double?
    let delay_ms: Double
    let loop: Bool
}

@MainActor
struct ZicClip {
    let frames: [NSImage]
    let metadata: SpriteMetadata
    var duration: TimeInterval { Double(frames.count) * metadata.delay_ms / 1000 }
    var grabRotationDegrees: Double { metadata.grab_rotation_degrees ?? 0 }
    var anchor: CGPoint {
        guard let point = metadata.anchor, point.count == 2 else {
            return CGPoint(x: Double(metadata.w) / 2, y: Double(metadata.h))
        }
        return CGPoint(x: point[0], y: point[1])
    }
    var grabAnchor: CGPoint {
        guard let point = metadata.grab_anchor, point.count == 2 else {
            return CGPoint(x: anchor.x, y: anchor.y - metadata.body_h * 0.46)
        }
        return CGPoint(x: point[0], y: point[1])
    }
    /// 프레임별 목덜이 기준점이 있으면 사용하고 없으면 공통 기준점으로 대체한다.
    func grabAnchor(frameIndex: Int) -> CGPoint {
        guard let points = metadata.grab_anchors, points.indices.contains(frameIndex),
              points[frameIndex].count == 2 else { return grabAnchor }
        return CGPoint(x: points[frameIndex][0], y: points[frameIndex][1])
    }
    /// 클립 고유 속도와 반복 여부로 표시할 프레임 번호를 계산한다.
    func frameIndex(elapsed: TimeInterval, animate: Bool) -> Int {
        animate ? SpriteTiming.frame(elapsed: elapsed, count: frames.count, delayMilliseconds: metadata.delay_ms, loop: metadata.loop) : 0
    }
    /// 붙잡힘 자세의 프레임별 크기 보정값을 반환하며 미지정 시 원래 배율을 사용한다.
    func grabScale(frameIndex: Int) -> Double {
        guard let scales = metadata.grab_scales, scales.indices.contains(frameIndex) else { return 1 }
        return scales[frameIndex]
    }
    /// 계산한 프레임 번호에 대응하는 캐시 이미지를 반환한다.
    func frame(elapsed: TimeInterval, animate: Bool) -> NSImage {
        frames[frameIndex(elapsed: elapsed, animate: animate)]
    }
}

@MainActor
final class ZicSprites {
    static let shared = ZicSprites()
    private let still: ZicClip
    private var clips: [ZicMotion: ZicClip] = [:]

    /// 번들에 포함된 모션을 한 번 읽고 누락 시 사용할 정지 이미지를 준비한다.
    private init() {
        guard let still = Self.load("still") else { preconditionFailure("Missing verified Zic still asset") }
        self.still = still
        for state in ZicMotion.allCases { clips[state] = Self.load(state.rawValue) }
    }
    /// 요청한 모션을 반환하며 누락된 클립은 정지 이미지로 대체한다.
    func clip(_ state: ZicMotion) -> ZicClip { clips[state] ?? still }
    /// 실제로 두 프레임 이상 있는 모션인지 확인한다.
    func hasAnimation(_ state: ZicMotion) -> Bool { (clips[state]?.frames.count ?? 0) > 1 }

    /// 메타데이터의 크기·프레임 수·시간·기준점을 검증한 뒤 시트를 분할해 메모리에 보관한다.
    private static func load(_ name: String) -> ZicClip? {
        guard let metadataURL = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Zic"),
              let imageURL = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Zic"),
              let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(SpriteMetadata.self, from: data),
              metadata.frames > 0, metadata.frames <= 256, metadata.w > 0, metadata.h > 0,
              metadata.body_h > 0, metadata.delay_ms > 0,
              let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == metadata.w * metadata.frames, image.height == metadata.h else { return nil }
        if let points = metadata.grab_anchors {
            guard points.count == metadata.frames, points.allSatisfy({ point in
                point.count == 2 && point.allSatisfy(\.isFinite) &&
                point[0] >= 0 && point[0] <= Double(metadata.w) &&
                point[1] >= 0 && point[1] <= Double(metadata.h)
            }) else { return nil }
        }
        if let rotation = metadata.grab_rotation_degrees {
            guard rotation.isFinite, abs(rotation) <= 45 else { return nil }
        }
        if let scales = metadata.grab_scales {
            guard scales.count == metadata.frames,
                  scales.allSatisfy({ $0.isFinite && (0.5...1.5).contains($0) }) else { return nil }
        }
        let frames = (0..<metadata.frames).compactMap { index -> NSImage? in
            guard let frame = image.cropping(to: CGRect(x: index * metadata.w, y: 0, width: metadata.w, height: metadata.h)) else { return nil }
            return NSImage(cgImage: frame, size: NSSize(width: metadata.w, height: metadata.h))
        }
        guard frames.count == metadata.frames else { return nil }
        return ZicClip(frames: frames, metadata: metadata)
    }
}
