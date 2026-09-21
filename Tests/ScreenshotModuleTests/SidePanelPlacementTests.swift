import CoreGraphics
import Testing
@testable import ScreenshotModule

/// 识别结果面板出现在选区旁边：右 → 左 → 下 → 上 → 选区内右下角
@Suite struct SidePanelPlacementTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    private let panel = CGSize(width: 380, height: 300)

    @Test func prefersRightSideTopAligned() {
        let origin = ToolbarPlacement.sidePanelOrigin(
            panelSize: panel, selection: CGRect(x: 200, y: 150, width: 600, height: 400), bounds: bounds)
        #expect(origin == CGPoint(x: 812, y: 150))        // x = 800 + 12
    }

    @Test func goesLeftWhenNoRoomOnTheRight() {
        let origin = ToolbarPlacement.sidePanelOrigin(
            panelSize: panel, selection: CGRect(x: 700, y: 150, width: 800, height: 400), bounds: bounds)
        #expect(origin == CGPoint(x: 308, y: 150))        // x = 700 - 12 - 380
    }

    @Test func goesBelowWhenNoRoomOnEitherSide() {
        let origin = ToolbarPlacement.sidePanelOrigin(
            panelSize: panel, selection: CGRect(x: 100, y: 50, width: 1400, height: 400), bounds: bounds)
        #expect(origin == CGPoint(x: 100, y: 462))        // y = 450 + 12
    }

    @Test func goesAboveWhenNoRoomBelow() {
        let origin = ToolbarPlacement.sidePanelOrigin(
            panelSize: panel, selection: CGRect(x: 100, y: 500, width: 1400, height: 450), bounds: bounds)
        #expect(origin == CGPoint(x: 100, y: 188))        // y = 500 - 12 - 300
    }

    @Test func goesInsideBottomRightForFullScreenSelection() {
        let origin = ToolbarPlacement.sidePanelOrigin(panelSize: panel, selection: bounds, bounds: bounds)
        #expect(origin == CGPoint(x: 1208, y: 688))       // 1600 - 12 - 380；1000 - 12 - 300
    }

    @Test func sidePlacementIsClampedVertically() {
        // 选区贴着屏幕底部：面板顶对齐会超出屏幕，要往上收
        let origin = ToolbarPlacement.sidePanelOrigin(
            panelSize: panel, selection: CGRect(x: 200, y: 900, width: 300, height: 100), bounds: bounds)
        #expect(origin == CGPoint(x: 512, y: 700))        // y = 1000 - 300
    }

    @Test func respectsNonZeroScreenOriginInLocalBounds() {
        let small = CGRect(x: 0, y: 0, width: 800, height: 500)
        let origin = ToolbarPlacement.sidePanelOrigin(
            panelSize: panel, selection: CGRect(x: 300, y: 100, width: 200, height: 100), bounds: small)
        // 右边剩 300、左边剩 300，都放不下 380；下方 500-212=288 也放不下 300；上方不够 → 选区内右下角并夹进屏幕
        #expect(origin.x >= 0)
        #expect(origin.y >= 0)
        #expect(origin.x + panel.width <= small.width)
        #expect(origin.y + panel.height <= small.height)
    }
}
