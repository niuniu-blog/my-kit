import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct ToolbarPlacementTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let toolbar = CGSize(width: 300, height: 40)
    private let label = CGSize(width: 90, height: 20)

    @Test func toolbarGoesBelowSelectionRightAligned() {
        let origin = ToolbarPlacement.toolbarOrigin(
            toolbarSize: toolbar, selection: CGRect(x: 200, y: 100, width: 500, height: 300), bounds: bounds)
        #expect(origin == CGPoint(x: 400, y: 408))       // x = 700 - 300；y = 400 + 8
    }

    @Test func toolbarGoesAboveWhenNoRoomBelow() {
        let origin = ToolbarPlacement.toolbarOrigin(
            toolbarSize: toolbar, selection: CGRect(x: 200, y: 400, width: 500, height: 380), bounds: bounds)
        #expect(origin == CGPoint(x: 400, y: 352))       // y = 400 - 8 - 40
    }

    @Test func toolbarGoesInsideWhenNoRoomAboveOrBelow() {
        let origin = ToolbarPlacement.toolbarOrigin(
            toolbarSize: toolbar, selection: CGRect(x: 0, y: 10, width: 1000, height: 780), bounds: bounds)
        #expect(origin == CGPoint(x: 692, y: 742))       // x = 1000 - 8 - 300；y = 790 - 8 - 40
    }

    @Test func toolbarNeverLeavesScreenHorizontally() {
        let origin = ToolbarPlacement.toolbarOrigin(
            toolbarSize: toolbar, selection: CGRect(x: 10, y: 100, width: 50, height: 50), bounds: bounds)
        #expect(origin == CGPoint(x: 0, y: 158))         // 60 - 300 < 0 → 贴左边
    }

    @Test func labelSitsAboveTopLeftCorner() {
        let origin = ToolbarPlacement.labelOrigin(
            labelSize: label, selection: CGRect(x: 200, y: 100, width: 500, height: 300), bounds: bounds)
        #expect(origin == CGPoint(x: 200, y: 76))        // y = 100 - 4 - 20
    }

    @Test func labelMovesInsideWhenSelectionTouchesTop() {
        let origin = ToolbarPlacement.labelOrigin(
            labelSize: label, selection: CGRect(x: 200, y: 10, width: 500, height: 300), bounds: bounds)
        #expect(origin == CGPoint(x: 204, y: 14))
    }

    @Test func labelStaysOnScreenAtRightEdge() {
        let origin = ToolbarPlacement.labelOrigin(
            labelSize: label, selection: CGRect(x: 980, y: 100, width: 20, height: 50), bounds: bounds)
        #expect(origin == CGPoint(x: 910, y: 76))
    }
}
