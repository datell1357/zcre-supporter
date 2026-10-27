// 기능 분류: ZCRE 색상과 공통 버튼 스타일
import SwiftUI

/// 2026-10-25 웹 화면의 CSS 토큰을 확인해 적용한 ZCRE 다크 테마다.
enum BunnyTheme {
    static let background = color(0x070A0F)
    static let surface = color(0x16181D)
    static let elevated = color(0x191C21)
    static let border = color(0x24272A)
    static let foreground = color(0xF9FAFC)
    static let muted = color(0x9FA1A4)
    static let ink = color(0x15171C)
    static let accent = color(0x86EFAC)
    static let success = color(0x22E66D)

    /// 정수 RGB 값을 SwiftUI 색상으로 변환한다.
    private static func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct ZCREButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    /// 강조·누름·비활성 상태에 맞춰 공통 버튼 색상과 모양을 구성한다.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .foregroundStyle(prominent ? BunnyTheme.ink : BunnyTheme.foreground)
            .background(prominent ? BunnyTheme.foreground : BunnyTheme.elevated, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(prominent ? .clear : BunnyTheme.border))
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
    }
}
