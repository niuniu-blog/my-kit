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

    // MARK: 标注样式栏

    private let styleBar = CGSize(width: 260, height: 36)

    @Test func styleBarGoesBelowAToolbarThatIsBelowTheSelection() {
        let selection = CGRect(x: 200, y: 100, width: 500, height: 300)
        let toolbarFrame = CGRect(x: 100, y: 408, width: 600, height: 40)
        let origin = ToolbarPlacement.styleBarOrigin(barSize: styleBar, toolbarFrame: toolbarFrame, selection: selection, bounds: bounds)
        #expect(origin == CGPoint(x: 100, y: 454))       // 448 + 6
    }

    @Test func styleBarGoesAboveAToolbarThatIsAboveTheSelection() {
        let selection = CGRect(x: 200, y: 400, width: 500, height: 380)
        let toolbarFrame = CGRect(x: 100, y: 352, width: 600, height: 40)
        let origin = ToolbarPlacement.styleBarOrigin(barSize: styleBar, toolbarFrame: toolbarFrame, selection: selection, bounds: bounds)
        #expect(origin == CGPoint(x: 100, y: 310))       // 352 - 6 - 36：不盖住选区
    }

    @Test func styleBarFlipsWhenThePreferredSideDoesNotFit() {
        // 工具条在选区下方，但已经贴近屏幕底部：样式栏改到工具条上方
        let selection = CGRect(x: 200, y: 300, width: 500, height: 440)
        let toolbarFrame = CGRect(x: 100, y: 748, width: 600, height: 40)
        let origin = ToolbarPlacement.styleBarOrigin(barSize: styleBar, toolbarFrame: toolbarFrame, selection: selection, bounds: bounds)
        #expect(origin == CGPoint(x: 100, y: 706))
    }

    @Test func styleBarStaysOnScreenHorizontally() {
        let selection = CGRect(x: 900, y: 100, width: 100, height: 100)
        let toolbarFrame = CGRect(x: 900, y: 208, width: 100, height: 40)
        let origin = ToolbarPlacement.styleBarOrigin(barSize: styleBar, toolbarFrame: toolbarFrame, selection: selection, bounds: bounds)
        #expect(origin == CGPoint(x: 740, y: 254))       // 1000 - 260
    }
}
