import AppKit
import Testing
@testable import Core

@Suite struct FloatingPanelTests {
    @Test func frameIsHorizontallyCenteredAndInUpperPart() {
        let visible = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let frame = FloatingPanel.frame(for: NSSize(width: 760, height: 460), inVisibleFrame: visible)

        #expect(frame.size == NSSize(width: 760, height: 460))
        #expect(frame.midX == visible.midX)
        #expect(frame.maxY == 800)     // 顶边距离可见区域顶部 20%
    }

    @Test func frameRespectsScreenOrigin() {
        // 第二块显示器：原点不在 (0,0)
        let visible = NSRect(x: 1600, y: -200, width: 1200, height: 800)
        let frame = FloatingPanel.frame(for: NSSize(width: 760, height: 460), inVisibleFrame: visible)

        #expect(frame.midX == visible.midX)
        #expect(frame.maxY == visible.maxY - 160)
    }

    @Test func frameStaysInsideSmallScreens() {
        let visible = NSRect(x: 0, y: 0, width: 800, height: 500)
        let frame = FloatingPanel.frame(for: NSSize(width: 760, height: 460), inVisibleFrame: visible)

        #expect(frame.minY >= visible.minY)
        #expect(frame.maxY <= visible.maxY)
    }
}
