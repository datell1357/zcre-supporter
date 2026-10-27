// 기능 분류: 클립 시간에 따른 안전한 프레임 선택
import Foundation

public enum SpriteTiming {
    /// 반복 클립은 순환하고 단발 클립은 마지막 프레임에서 멈추며 잘못된 시간 값은 안전하게 처리한다.
    public static func frame(elapsed: TimeInterval, count: Int, delayMilliseconds: Double, loop: Bool) -> Int {
        guard count > 1, elapsed.isFinite, delayMilliseconds.isFinite, delayMilliseconds > 0 else { return 0 }
        let position = max(0, elapsed) / (delayMilliseconds / 1000)
        if loop { return Int(position.truncatingRemainder(dividingBy: Double(count))) }
        return Int(min(Double(count - 1), position))
    }
}
