import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct PinZoomTests {
    @Test func scrollingUpZoomsInAndDownZoomsOut() {
        #expect(PinZoom.scale(current: 1, scrollDeltaY: 10) == 1.1)
        #expect(PinZoom.scale(current: 1, scrollDeltaY: -10) == 0.9)
        #expect(PinZoom.scale(current: 2, scrollDeltaY: 0) == 2)
    }

    @Test func scaleIsClampedBetweenTenAndFiveHundredPercent() {
        #expect(PinZoom.scale(current: 4.9, scrollDeltaY: 50) == 5)
        #expect(PinZoom.scale(current: 0.11, scrollDeltaY: -50) == 0.1)
        #expect(PinZoom.scale(current: 1, scrollDeltaY: -500) == 0.1)
    }

    @Test func frameScalesAroundItsCenter() {
        let current = CGRect(x: 100, y: 200, width: 400, height: 200)      // 中心 (300, 300)
        let frame = PinZoom.frame(current: current, baseSize: CGSize(width: 400, height: 200), scale: 2)

        #expect(frame == CGRect(x: -100, y: 100, width: 800, height: 400))
        #expect(frame.midX == 300)
        #expect(frame.midY == 300)
    }

    @Test func frameUsesBaseSizeNotCurrentSize() {
        // 已经放大到 2× 的窗口再设回 1×，应当回到原始大小，而不是在当前大小上继续乘
        let current = CGRect(x: -100, y: 100, width: 800, height: 400)
        let frame = PinZoom.frame(current: current, baseSize: CGSize(width: 400, height: 200), scale: 1)
        #expect(frame == CGRect(x: 100, y: 200, width: 400, height: 200))
    }
}
