import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct SelectionModelTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let frontWindow = CGRect(x: 100, y: 100, width: 400, height: 300)
    private let backWindow = CGRect(x: 0, y: 0, width: 900, height: 700)

    private func makeModel() -> SelectionModel {
        SelectionModel(bounds: bounds, windows: [frontWindow, backWindow])
    }

    /// 拖出一个选区并松手。
    private func makeSelected(from start: CGPoint, to end: CGPoint) -> SelectionModel {
        var model = makeModel()
        model.mouseDown(at: start)
        model.mouseDragged(to: end)
        model.mouseUp(at: end)
        return model
    }

    // MARK: 悬停与单击选窗

    @Test func hoveringHighlightsTopWindowUnderMouse() {
        var model = makeModel()
        model.mouseMoved(to: CGPoint(x: 200, y: 200))
        #expect(model.highlight == frontWindow)
        #expect(model.selection == nil)
        #expect(!model.hasConfirmedSelection)

        model.mouseMoved(to: CGPoint(x: 700, y: 600))
        #expect(model.highlight == backWindow)

        model.mouseMoved(to: CGPoint(x: 950, y: 750))
        #expect(model.highlight == nil)
    }

    @Test func clickingWithoutDraggingSelectsHoveredWindow() {
        var model = makeModel()
        model.mouseDown(at: CGPoint(x: 200, y: 200))
        model.mouseDragged(to: CGPoint(x: 201, y: 201))     // 不足 3pt，仍算单击
        model.mouseUp(at: CGPoint(x: 201, y: 201))

        #expect(model.selection == frontWindow)
        #expect(model.hasConfirmedSelection)
        #expect(!model.isAdjusting)
    }

    @Test func clickingWhereThereIsNoWindowDoesNothing() {
        var model = makeModel()
        model.mouseDown(at: CGPoint(x: 950, y: 750))
        model.mouseUp(at: CGPoint(x: 950, y: 750))
        #expect(model.selection == nil)
        #expect(!model.hasConfirmedSelection)
    }

    // MARK: 框选

    @Test func draggingDrawsSelectionAndHidesToolbarUntilMouseUp() {
        var model = makeModel()
        model.mouseDown(at: CGPoint(x: 50, y: 60))
        model.mouseDragged(to: CGPoint(x: 250, y: 200))

        #expect(model.selection == CGRect(x: 50, y: 60, width: 200, height: 140))
        #expect(model.isAdjusting)
        #expect(!model.hasConfirmedSelection)

        model.mouseUp(at: CGPoint(x: 250, y: 200))
        #expect(model.selection == CGRect(x: 50, y: 60, width: 200, height: 140))
        #expect(model.hasConfirmedSelection)
        #expect(!model.isAdjusting)
    }

    @Test func draggingUpAndLeftIsNormalised() {
        let model = makeSelected(from: CGPoint(x: 300, y: 300), to: CGPoint(x: 100, y: 150))
        #expect(model.selection == CGRect(x: 100, y: 150, width: 200, height: 150))
    }

    @Test func selectionIsClampedToScreenAndRoundedToWholePoints() {
        let model = makeSelected(from: CGPoint(x: 900.4, y: 700.6), to: CGPoint(x: 1200, y: 900))
        #expect(model.selection == CGRect(x: 900, y: 701, width: 100, height: 99))
    }

    @Test func tooSmallSelectionIsDiscarded() {
        let model = makeSelected(from: CGPoint(x: 950, y: 750), to: CGPoint(x: 955, y: 790))   // 宽只有 5pt
        #expect(model.selection == nil)
        #expect(!model.hasConfirmedSelection)
    }

    @Test func hoverIsIgnoredOnceThereIsASelection() {
        var model = makeSelected(from: CGPoint(x: 600, y: 600), to: CGPoint(x: 700, y: 700))
        model.mouseMoved(to: CGPoint(x: 200, y: 200))
        #expect(model.highlight == CGRect(x: 600, y: 600, width: 100, height: 100))
    }

    // MARK: 移动

    @Test func draggingInsideMovesSelection() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        model.mouseDown(at: CGPoint(x: 200, y: 150))
        model.mouseDragged(to: CGPoint(x: 250, y: 180))
        #expect(model.isAdjusting)
        model.mouseUp(at: CGPoint(x: 250, y: 180))

        #expect(model.selection == CGRect(x: 150, y: 130, width: 200, height: 100))
        #expect(model.hasConfirmedSelection)
    }

    @Test func movingStopsAtScreenEdgesAndKeepsSize() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        model.mouseDown(at: CGPoint(x: 200, y: 150))
        model.mouseDragged(to: CGPoint(x: 5000, y: -5000))
        model.mouseUp(at: CGPoint(x: 5000, y: -5000))

        #expect(model.selection == CGRect(x: 800, y: 0, width: 200, height: 100))
    }

    // MARK: 缩放

    @Test func handlesAreOnlyAvailableOnConfirmedSelection() {
        var model = makeModel()
        #expect(model.handle(at: CGPoint(x: 100, y: 100)) == nil)

        model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        #expect(model.handle(at: CGPoint(x: 100, y: 100)) == .topLeft)
        #expect(model.handle(at: CGPoint(x: 200, y: 100)) == .top)
        #expect(model.handle(at: CGPoint(x: 304, y: 196)) == .bottomRight)    // 6pt 命中半径内
        #expect(model.handle(at: CGPoint(x: 300, y: 150)) == .right)
        #expect(model.handle(at: CGPoint(x: 200, y: 150)) == nil)             // 选区中间不是手柄
    }

    @Test func handlePointsCoverCornersAndEdgeMidpoints() {
        let points = SelectionModel.handlePoints(for: CGRect(x: 0, y: 0, width: 100, height: 60))
        #expect(points.count == 8)
        #expect(points.first { $0.handle == .bottom }?.point == CGPoint(x: 50, y: 60))
        #expect(points.first { $0.handle == .left }?.point == CGPoint(x: 0, y: 30))
    }

    @Test func draggingCornerHandleResizesTwoEdges() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        model.mouseDown(at: CGPoint(x: 300, y: 200))                 // 右下角
        model.mouseDragged(to: CGPoint(x: 400, y: 260))
        model.mouseUp(at: CGPoint(x: 400, y: 260))
        #expect(model.selection == CGRect(x: 100, y: 100, width: 300, height: 160))
    }

    @Test func draggingEdgeHandleResizesOnlyThatEdge() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        model.mouseDown(at: CGPoint(x: 200, y: 100))                 // 上边中点
        model.mouseDragged(to: CGPoint(x: 555, y: 40))               // 水平方向的移动被忽略
        model.mouseUp(at: CGPoint(x: 555, y: 40))
        #expect(model.selection == CGRect(x: 100, y: 40, width: 200, height: 160))
    }

    @Test func resizingCannotShrinkBelowMinimumOrFlip() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        model.mouseDown(at: CGPoint(x: 100, y: 150))                 // 左边中点
        model.mouseDragged(to: CGPoint(x: 900, y: 150))              // 拖过右边
        model.mouseUp(at: CGPoint(x: 900, y: 150))
        #expect(model.selection == CGRect(x: 292, y: 100, width: 8, height: 100))
    }

    @Test func resizingIsClampedToScreen() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        model.mouseDown(at: CGPoint(x: 100, y: 100))                 // 左上角
        model.mouseDragged(to: CGPoint(x: -400, y: -400))
        model.mouseUp(at: CGPoint(x: -400, y: -400))
        #expect(model.selection == CGRect(x: 0, y: 0, width: 300, height: 200))
    }

    // MARK: 选区外操作

    @Test func draggingOutsideSelectionStartsANewOne() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        model.mouseDown(at: CGPoint(x: 500, y: 500))
        model.mouseDragged(to: CGPoint(x: 650, y: 620))
        model.mouseUp(at: CGPoint(x: 650, y: 620))
        #expect(model.selection == CGRect(x: 500, y: 500, width: 150, height: 120))
    }

    @Test func clickingOutsideSelectionKeepsIt() {
        var model = makeSelected(from: CGPoint(x: 600, y: 600), to: CGPoint(x: 700, y: 700))
        model.mouseDown(at: CGPoint(x: 200, y: 200))                 // 这里有窗口，但已有选区时单击不换
        model.mouseUp(at: CGPoint(x: 200, y: 200))
        #expect(model.selection == CGRect(x: 600, y: 600, width: 100, height: 100))
        #expect(model.hasConfirmedSelection)
    }

    // MARK: 取消

    @Test func cancelFirstClearsSelectionThenAsksToExit() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))

        #expect(model.cancel() == false)
        #expect(model.selection == nil)
        #expect(model.highlight == nil)

        #expect(model.cancel() == true)
    }

    @Test func cancelWhileDraggingClearsWithoutExiting() {
        var model = makeModel()
        model.mouseDown(at: CGPoint(x: 100, y: 100))
        model.mouseDragged(to: CGPoint(x: 200, y: 200))
        #expect(model.cancel() == false)
        #expect(model.selection == nil)
        #expect(!model.isAdjusting)
    }

    @Test func resetClearsEverything() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        model.reset()
        #expect(model.selection == nil)
        #expect(!model.hasConfirmedSelection)
        #expect(model.cancel() == true)
    }
}
