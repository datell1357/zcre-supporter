import Testing
import Foundation
@testable import ZCRECore

@Test func quickMenuKeepsPetAndWorkingLabelClear() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let anchor = CGRect(x: 640, y: 360, width: 90, height: 110)
    for (count, home) in [(3, true), (5, true), (8, false), (6, false)] {
        let layout = PetQuickMenuLayout(anchor: anchor, screen: screen, count: count, home: home)
        #expect(layout.buttons.count == count)
        #expect(layout.summary.minY > anchor.maxY)
        #expect(!layout.summary.intersects(layout.protectedFrame))
        #expect(layout.protectedFrames[1].contains(CGRect(x: anchor.midX - 55, y: anchor.minY - 28, width: 110, height: 22)))
        for button in layout.buttons { #expect(!layout.protectedFrames.contains { button.intersects($0) }) }
    }
}

@Test func quickMenuAvoidsEdgesAndOtherButtonsAtEveryPetSize() {
    for screen in [CGRect(x: 0, y: 24, width: 1280, height: 720), CGRect(x: -1440, y: -900, width: 1440, height: 900)] {
        for scale in [0.7, 1.0, 1.5] {
            let size = PetLayout(scale: scale).rabbitSize
            for x in [screen.minX - 20, screen.midX, screen.maxX - size.width + 20] {
                for y in [screen.minY - 15, screen.midY, screen.maxY - size.height + 15] {
                    let anchor = CGRect(origin: CGPoint(x: x, y: y), size: size)
                    for (count, home) in [(3, true), (5, true), (8, false), (6, false)] {
                        let layout = PetQuickMenuLayout(anchor: anchor, screen: screen, count: count, home: home)
                        #expect(layout.buttons.count == count)
                        #expect(screen.contains(layout.summary))
                        #expect(!layout.summary.intersects(layout.protectedFrame))
                        for (i, button) in layout.buttons.enumerated() {
                            #expect(screen.contains(button))
                            #expect(!layout.protectedFrames.contains { button.intersects($0) })
                            #expect(!button.intersects(layout.summary))
                            for other in layout.buttons.dropFirst(i + 1) { #expect(!button.intersects(other)) }
                        }
                    }
                }
            }
        }
    }
}

@Test func quickMenuHomeStaysCloseToPet() {
    let anchor = CGRect(x: 640, y: 360, width: 90, height: 110)
    let layout = PetQuickMenuLayout(anchor: anchor, screen: CGRect(x: 0, y: 0, width: 1440, height: 900), count: 3, home: true)
    #expect(layout.radius <= 116)
    #expect(layout.summary.minY - anchor.maxY <= 10)
    for button in layout.buttons {
        #expect(button.width == 56)
        #expect(abs(hypot(button.midX - anchor.midX, button.midY - anchor.midY) - layout.radius) < 0.01)
    }
}

@Test func quickMenuSpacesHomeToolsEvenly() {
    let anchor = CGRect(x: 640, y: 360, width: 90, height: 110)
    let layout = PetQuickMenuLayout(anchor: anchor, screen: CGRect(x: 0, y: 0, width: 1440, height: 900), count: 5, home: true)
    #expect(layout.buttons.count == 5)
    #expect(layout.radius <= 116)
    for (index, angle) in [(2, -30.0), (3, -150.0)] {
        let button = layout.buttons[index]
        let actual = atan2(button.midY - anchor.midY, button.midX - anchor.midX) * 180 / .pi
        #expect(abs(actual - angle) < 0.01)
    }
    #expect(abs(layout.buttons[4].midX - anchor.midX) < 0.01)
    let ordered = [0, 3, 4, 2, 1].map { layout.buttons[$0] }
    for i in 0..<4 {
        let gap = hypot(ordered[i].midX - ordered[i+1].midX, ordered[i].midY - ordered[i+1].midY)
        #expect(abs(gap - layout.radius) < 0.01)
    }
}

@Test func quickMenuCloseStaysAtSixAtSmallPetSize() {
    let size = PetLayout(scale: 0.7).rabbitSize
    let anchor = CGRect(origin: CGPoint(x: 640, y: 360), size: size)
    let layout = PetQuickMenuLayout(anchor: anchor, screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), count: 5, home: true)
    #expect(abs(layout.buttons[4].midX - anchor.midX) < 0.01)
    let ordered = [0, 3, 4, 2, 1].map { layout.buttons[$0] }
    for i in 0..<4 {
        let gap = hypot(ordered[i].midX - ordered[i+1].midX, ordered[i].midY - ordered[i+1].midY)
        #expect(abs(gap - layout.radius) < 0.01)
    }
}

@Test func quickMenuProtectsLongWorkingLabels() {
    let anchor = CGRect(x: 640, y: 360, width: 90, height: 110)
    for width in [110.0, 170.0, 240.0] {
        let layout = PetQuickMenuLayout(anchor: anchor, screen: CGRect(x: 0, y: 0, width: 1440, height: 900), count: 5, home: true, labelWidth: width)
        #expect(layout.buttons.count == 5)
        for button in layout.buttons {
            #expect(!layout.protectedFrames.contains { button.intersects($0) })
        }
    }
}
