import Testing
import Foundation
@testable import ZCRECore

@Test func homeMenuUsesFourSymmetricCircularButtons() {
    let anchor = CGRect(x: 640, y: 360, width: 90, height: 110)
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let layout = PetQuickMenuLayout(anchor: anchor, screen: screen, count: 4, home: true)

    #expect(layout.buttons.count == 4)
    #expect(!layout.usesFallbackGrid)
    #expect(layout.radius >= 78 && layout.radius <= 92)
    #expect(layout.buttons.allSatisfy { $0.size == PetQuickMenuLayout.preferredButtonSize })
    for button in layout.buttons {
        #expect(screen.contains(button))
        #expect(!button.intersects(layout.protectedFrame))
        #expect(!button.intersects(layout.summary))
    }
    for index in [0, 1] {
        let left = layout.buttons[index]
        let right = layout.buttons[3 - index]
        #expect(abs(left.midY - right.midY) < 0.01)
        #expect(abs((anchor.midX - left.midX) - (right.midX - anchor.midX)) < 0.01)
    }
}

@Test func summaryAlwaysSitsDirectlyAboveThePet() {
    let anchor = CGRect(x: 640, y: 360, width: 90, height: 110)
    let layout = PetQuickMenuLayout(anchor: anchor, screen: CGRect(x: 0, y: 0, width: 1440, height: 900), count: 7, home: false)
    #expect(abs(layout.summary.midX - anchor.midX) < 0.01)
    #expect(abs(layout.summary.minY - (anchor.maxY + 8)) < 0.01)
}

@Test func toolMenusKeepEveryButtonOnTheSameCircle() {
    let anchor = CGRect(x: 640, y: 360, width: 90, height: 110)
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    for count in [5, 6, 7] {
        let layout = PetQuickMenuLayout(anchor: anchor, screen: screen, count: count, home: false)
        #expect(layout.buttons.count == count)
        #expect(layout.radius <= 85)
        let expectedSize = count >= 7 ? CGSize(width: 40, height: 40) : count >= 6 ? CGSize(width: 44, height: 44) : CGSize(width: 48, height: 48)
        #expect(layout.buttons.allSatisfy { $0.size == expectedSize })
        for (index, button) in layout.buttons.enumerated() {
            let distance = hypot(button.midX - anchor.midX, button.midY - anchor.midY)
            #expect(abs(distance - layout.radius) < 0.01)
            #expect(!button.intersects(layout.summary))
            #expect(!layout.protectedFrames.contains { button.intersects($0) })
            for other in layout.buttons.dropFirst(index + 1) { #expect(!button.intersects(other)) }
        }
    }
}

@Test func edgePositionsKeepEveryToolReachable() {
    for screen in [CGRect(x: 0, y: 24, width: 1280, height: 720), CGRect(x: -1440, y: -900, width: 1440, height: 900)] {
        for scale in [0.7, 1.0, 1.5] {
            let size = PetLayout(scale: scale).rabbitSize
            for x in [screen.minX - 20, screen.midX, screen.maxX - size.width + 20] {
                for y in [screen.minY - 15, screen.midY, screen.maxY - size.height + 15] {
                    let anchor = CGRect(origin: CGPoint(x: x, y: y), size: size)
                    let layout = PetQuickMenuLayout(anchor: anchor, screen: screen, count: 7, home: false)
                    #expect(layout.buttons.count == 7)
                    #expect(abs(layout.summary.midX - anchor.midX) < 0.01)
                    for (index, button) in layout.buttons.enumerated() {
                        #expect(screen.contains(button))
                        #expect(!layout.protectedFrames.contains { button.intersects($0) })
                        for other in layout.buttons.dropFirst(index + 1) { #expect(!button.intersects(other)) }
                    }
                }
            }
        }
    }
}

// 저장 기본값인 0.7배 지크에서 하위 메뉴가 현황 박스를 피하려고 크게 벌어지던 회귀를 막는다.
@Test func submenusHugSmallPet() {
    let size = PetLayout(scale: 0.7).rabbitSize
    let anchor = CGRect(origin: CGPoint(x: 700, y: 400), size: size)
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1080)
    let home = PetQuickMenuLayout(anchor: anchor, screen: screen, count: 4, home: true)
    for count in [5, 6, 7] {
        let layout = PetQuickMenuLayout(anchor: anchor, screen: screen, count: count, home: false)
        #expect(!layout.usesFallbackGrid)
        #expect(layout.radius <= home.radius + 3)
        #expect(layout.buttons.allSatisfy { !$0.intersects(layout.summary) })
    }
}
