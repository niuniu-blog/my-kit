import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct AnnotationModelTests {
    private let selection = CGSize(width: 400, height: 300)

    private func makeModel(tool: AnnotationTool?) -> AnnotationModel {
        var model = AnnotationModel()
        if let tool { model.toggleTool(tool) }
        return model
    }

    /// 完整的一次 按下-拖动-松开
    private func drag(_ model: inout AnnotationModel, from start: CGPoint, to end: CGPoint, shift: Bool = false) {
        _ = model.mouseDown(at: start, in: selection, shift: shift)
        model.mouseDragged(to: end, shift: shift)
        model.mouseUp(at: end, shift: shift)
    }

    // MARK: 工具选择与锁定

    @Test func startsWithRedMediumAndNoTool() {
        let model = AnnotationModel()
        #expect(model.tool == nil)
        #expect(model.color == .red)
        #expect(model.size == .medium)
        #expect(!model.locksSelection)
        #expect(!model.canUndo)
        #expect(!model.canRedo)
    }

    @Test func togglingSelectsSwitchesAndDeselects() {
        var model = AnnotationModel()
        model.toggleTool(.arrow)
        #expect(model.tool == .arrow)
        model.toggleTool(.pen)
        #expect(model.tool == .pen)
        model.toggleTool(.pen)
        #expect(model.tool == nil)
    }

    @Test func selectionIsLockedWhileAToolIsSelectedOrAnnotationsExist() {
        var model = makeModel(tool: .rectangle)
        #expect(model.locksSelection)
        drag(&model, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 40))
        model.deselectTool()
        #expect(model.locksSelection)            // 没有工具，但有标注
        model.undo()
        #expect(!model.locksSelection)           // 全部撤销且没有工具：解除锁定
    }

    @Test func mouseDownIsIgnoredWithoutAToolOrOutsideTheSelection() {
        var noTool = AnnotationModel()
        #expect(noTool.mouseDown(at: CGPoint(x: 10, y: 10), in: selection, shift: false) == .ignored)

        var model = makeModel(tool: .rectangle)
        #expect(model.mouseDown(at: CGPoint(x: 500, y: 10), in: selection, shift: false) == .ignored)
        model.mouseDragged(to: CGPoint(x: 100, y: 100), shift: false)
        model.mouseUp(at: CGPoint(x: 100, y: 100), shift: false)
        #expect(model.items.isEmpty)
        #expect(model.inProgress == nil)
    }

    // MARK: 每种工具

    @Test func rectangleEllipseAndMosaicProduceNormalizedRects() {
        let expected = CGRect(x: 20, y: 30, width: 100, height: 50)
        for (tool, kind) in [
            (AnnotationTool.rectangle, Annotation.Kind.rectangle(expected)),
            (.ellipse, .ellipse(expected)),
            (.mosaic, .mosaic(expected)),
        ] {
            var model = makeModel(tool: tool)
            drag(&model, from: CGPoint(x: 120, y: 80), to: CGPoint(x: 20, y: 30))
            #expect(model.items == [Annotation(kind: kind, color: .red, size: .medium)])
        }
    }

    @Test func shiftConstrainsRectangleToSquare() {
        var model = makeModel(tool: .rectangle)
        drag(&model, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 110, y: 40), shift: true)
        #expect(model.items.first?.kind == .rectangle(CGRect(x: 10, y: 10, width: 100, height: 100)))
    }

    @Test func lineAndArrowKeepDirection() {
        var line = makeModel(tool: .line)
        drag(&line, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 200, y: 90))
        #expect(line.items.first?.kind == .line(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 200, y: 90)))

        var arrow = makeModel(tool: .arrow)
        drag(&arrow, from: CGPoint(x: 200, y: 90), to: CGPoint(x: 10, y: 10))
        #expect(arrow.items.first?.kind == .arrow(from: CGPoint(x: 200, y: 90), to: CGPoint(x: 10, y: 10)))
    }

    @Test func shiftSnapsArrowToHorizontal() throws {
        var model = makeModel(tool: .arrow)
        drag(&model, from: CGPoint(x: 10, y: 100), to: CGPoint(x: 210, y: 110), shift: true)
        guard case .arrow(_, let tip) = try #require(model.items.first).kind else {
            Issue.record("应该是箭头")
            return
        }
        #expect(abs(tip.y - 100) < 0.001)
        #expect(tip.x > 209)
    }

    @Test func penCollectsThePath() {
        var model = makeModel(tool: .pen)
        _ = model.mouseDown(at: CGPoint(x: 10, y: 10), in: selection, shift: false)
        model.mouseDragged(to: CGPoint(x: 20, y: 15), shift: false)
        model.mouseDragged(to: CGPoint(x: 20.2, y: 15.1), shift: false)     // 离上一个点不足 1pt：不记
        model.mouseDragged(to: CGPoint(x: 30, y: 30), shift: false)
        #expect(model.inProgress?.kind == .pen([CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 15), CGPoint(x: 30, y: 30)]))
        model.mouseUp(at: CGPoint(x: 30, y: 30), shift: false)
        #expect(model.items.count == 1)
        #expect(model.inProgress == nil)
    }

    @Test func highlighterWithShiftIsAStraightLine() {
        var model = makeModel(tool: .highlighter)
        _ = model.mouseDown(at: CGPoint(x: 10, y: 50), in: selection, shift: true)
        model.mouseDragged(to: CGPoint(x: 100, y: 58), shift: true)
        model.mouseUp(at: CGPoint(x: 200, y: 52), shift: true)
        #expect(model.items.first?.kind == .highlighter([CGPoint(x: 10, y: 50), CGPoint(x: 200, y: 52)]))
    }

    @Test func endPointsOutsideTheSelectionAreKeptAsIs() {
        // 拖出选区的部分由渲染时的裁剪负责，这里不夹取
        var model = makeModel(tool: .line)
        drag(&model, from: CGPoint(x: 390, y: 290), to: CGPoint(x: 600, y: 500))
        #expect(model.items.first?.kind == .line(from: CGPoint(x: 390, y: 290), to: CGPoint(x: 600, y: 500)))
    }

    @Test func tinyDragsAndSinglePointStrokesAreIgnored() {
        for tool in [AnnotationTool.rectangle, .ellipse, .line, .arrow, .mosaic] {
            var model = makeModel(tool: tool)
            drag(&model, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 51, y: 52))
            #expect(model.items.isEmpty, "\(tool)")
        }
        for tool in [AnnotationTool.pen, .highlighter] {
            var model = makeModel(tool: tool)
            _ = model.mouseDown(at: CGPoint(x: 50, y: 50), in: selection, shift: false)
            model.mouseUp(at: CGPoint(x: 50, y: 50), shift: false)
            #expect(model.items.isEmpty, "\(tool)")
        }
    }

    @Test func numberToolPlacesIncrementingNumbersImmediately() {
        var model = makeModel(tool: .number)
        #expect(model.mouseDown(at: CGPoint(x: 10, y: 10), in: selection, shift: false) == .placedNumber)
        #expect(model.mouseDown(at: CGPoint(x: 50, y: 10), in: selection, shift: false) == .placedNumber)
        #expect(model.items.map(\.kind) == [.number(1, center: CGPoint(x: 10, y: 10)), .number(2, center: CGPoint(x: 50, y: 10))])

        model.undo()
        #expect(model.nextNumber == 2)           // 撤销后编号回退
        _ = model.mouseDown(at: CGPoint(x: 90, y: 10), in: selection, shift: false)
        #expect(model.items.last?.kind == .number(2, center: CGPoint(x: 90, y: 10)))
    }

    @Test func numbersOnlyCountNumberAnnotations() {
        var model = makeModel(tool: .rectangle)
        drag(&model, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 60))
        model.toggleTool(.number)
        _ = model.mouseDown(at: CGPoint(x: 100, y: 100), in: selection, shift: false)
        #expect(model.items.last?.kind == .number(1, center: CGPoint(x: 100, y: 100)))
    }

    @Test func textToolAsksTheViewForAnEditorThenPlacesText() {
        var model = makeModel(tool: .text)
        #expect(model.mouseDown(at: CGPoint(x: 30, y: 40), in: selection, shift: false) == .beginText(at: CGPoint(x: 30, y: 40)))
        #expect(model.items.isEmpty)

        model.placeText("第一行\nsecond", at: CGPoint(x: 30, y: 40))
        #expect(model.items == [Annotation(kind: .text("第一行\nsecond", origin: CGPoint(x: 30, y: 40)), color: .red, size: .medium)])
    }

    @Test func blankTextProducesNothing() {
        var model = makeModel(tool: .text)
        model.placeText("  \n ", at: .zero)
        model.placeText("", at: .zero)
        #expect(model.items.isEmpty)
    }

    @Test func annotationsCarryTheCurrentColorAndSize() {
        var model = makeModel(tool: .line)
        model.color = .blue
        model.size = .large
        drag(&model, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50))
        #expect(model.items.first?.color == .blue)
        #expect(model.items.first?.size == .large)
    }

    // MARK: 撤销 / 重做 / 重置

    @Test func undoRedoAndNewAnnotationClearsRedo() {
        var model = makeModel(tool: .line)
        drag(&model, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 0))
        drag(&model, from: CGPoint(x: 0, y: 10), to: CGPoint(x: 50, y: 10))
        #expect(model.items.count == 2)

        model.undo()
        #expect(model.items.count == 1)
        #expect(model.canRedo)
        model.redo()
        #expect(model.items.count == 2)
        #expect(!model.canRedo)

        model.undo()
        drag(&model, from: CGPoint(x: 0, y: 20), to: CGPoint(x: 50, y: 20))      // 新标注
        #expect(!model.canRedo)
        #expect(model.items.count == 2)

        model.undo()
        model.undo()
        model.undo()                                                          // 多撤销一次也没事
        #expect(model.items.isEmpty)
    }

    @Test func switchingToolAbandonsTheStrokeInProgress() {
        var model = makeModel(tool: .pen)
        _ = model.mouseDown(at: CGPoint(x: 10, y: 10), in: selection, shift: false)
        model.mouseDragged(to: CGPoint(x: 40, y: 40), shift: false)
        model.toggleTool(.arrow)
        #expect(model.inProgress == nil)
        model.mouseUp(at: CGPoint(x: 40, y: 40), shift: false)
        #expect(model.items.isEmpty)
    }

    @Test func resetClearsEverythingButKeepsStyle() {
        var model = makeModel(tool: .line)
        model.color = .green
        model.size = .small
        drag(&model, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 0))
        model.undo()

        model.reset()

        #expect(model.tool == nil)
        #expect(model.items.isEmpty)
        #expect(!model.canRedo)
        #expect(!model.locksSelection)
        #expect(model.color == .green)
        #expect(model.size == .small)
    }
}

@Suite struct AnnotationSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsToRedMedium() {
        let settings = AnnotationSettings(defaults: makeDefaults())
        #expect(settings.color == .red)
        #expect(settings.size == .medium)
    }

    @Test func remembersChoices() {
        let defaults = makeDefaults()
        AnnotationSettings(defaults: defaults).color = .blue
        AnnotationSettings(defaults: defaults).size = .large
        #expect(AnnotationSettings(defaults: defaults).color == .blue)
        #expect(AnnotationSettings(defaults: defaults).size == .large)
    }

    @Test func unknownStoredValuesFallBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set("purple", forKey: AnnotationSettings.colorKey)
        defaults.set("huge", forKey: AnnotationSettings.sizeKey)
        #expect(AnnotationSettings(defaults: defaults).color == .red)
        #expect(AnnotationSettings(defaults: defaults).size == .medium)
    }

    @Test func screenshotSettingsShareTheSameDefaults() {
        let defaults = makeDefaults()
        ScreenshotSettings(defaults: defaults).annotation.color = .green
        #expect(AnnotationSettings(defaults: defaults).color == .green)
    }
}
