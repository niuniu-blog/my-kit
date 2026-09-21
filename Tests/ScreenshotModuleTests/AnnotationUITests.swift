import AppKit
import Foundation
import Testing
@testable import ScreenshotModule

/// 界面部件的冒烟测试：能创建、按钮齐全、点击能把指令送出来。真正的手感靠手动验收。
@MainActor
@Suite struct AnnotationUITests {
    private func buttons(in view: NSView) -> [NSButton] {
        view.subviews.flatMap { subview -> [NSButton] in
            (subview as? NSButton).map { [$0] } ?? buttons(in: subview)
        }
    }

    private func makeDefaults() -> UserDefaults {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func whiteImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        return try #require(context.makeImage())
    }

    @Test func toolbarHasNineToolsUndoRedoAndFiveActions() {
        let toolbar = CaptureToolbar()
        let all = buttons(in: toolbar)
        #expect(all.count == 16)
        let hints = all.compactMap(\.toolTip)
        for tool in AnnotationTool.allCases {
            #expect(hints.contains(tool.displayName), "\(tool.displayName)")
        }
        #expect(hints.contains("撤销  ⌘Z"))
        #expect(hints.contains("重做  ⇧⌘Z"))
        #expect(hints.contains("复制到剪切板  ↩"))
        #expect(toolbar.frame.width > 300)
        #expect(toolbar.frame.height > 20)
    }

    @Test func toolbarSendsToolTogglesAndCommands() throws {
        let toolbar = CaptureToolbar()
        var toggled: [AnnotationTool] = []
        var commands: [OverlayCommand] = []
        toolbar.onToolToggle = { toggled.append($0) }
        toolbar.onCommand = { commands.append($0) }
        toolbar.update(selectedTool: nil, canUndo: true, canRedo: true)
        let all = buttons(in: toolbar)

        try #require(all.first { $0.toolTip == "箭头" }).performClick(nil)
        try #require(all.first { $0.toolTip == "马赛克" }).performClick(nil)
        try #require(all.first { $0.toolTip == "撤销  ⌘Z" }).performClick(nil)
        try #require(all.first { $0.toolTip == "重做  ⇧⌘Z" }).performClick(nil)
        try #require(all.first { $0.toolTip == "保存为 PNG 文件  ⌘S" }).performClick(nil)

        #expect(toggled == [.arrow, .mosaic])
        #expect(commands == [.undo, .redo, .perform(.save)])
    }

    @Test func toolbarReflectsModelState() throws {
        let toolbar = CaptureToolbar()
        let all = buttons(in: toolbar)
        let undo = try #require(all.first { $0.toolTip == "撤销  ⌘Z" })
        let pen = try #require(all.first { $0.toolTip == "画笔" })
        #expect(!undo.isEnabled)
        #expect(pen.state == .off)

        toolbar.update(selectedTool: .pen, canUndo: true, canRedo: false)

        #expect(undo.isEnabled)
        #expect(pen.state == .on)
        #expect(all.filter { $0.state == .on && AnnotationTool.allCases.map(\.displayName).contains($0.toolTip ?? "") }.count == 1)
    }

    @Test func styleBarHidesColorsForMosaicAndReportsChoices() throws {
        let bar = AnnotationStyleBar()
        bar.update(color: .red, size: .medium, showsColors: true)
        let fullWidth = bar.frame.width
        var colors: [AnnotationColor] = []
        var sizes: [AnnotationSize] = []
        bar.onColor = { colors.append($0) }
        bar.onSize = { sizes.append($0) }
        let all = buttons(in: bar)
        #expect(all.count == 9)

        try #require(all.first { $0.toolTip == "蓝" }).performClick(nil)
        try #require(all.first { $0.title == "粗" }).performClick(nil)
        #expect(colors == [.blue])
        #expect(sizes == [.large])

        bar.update(color: .red, size: .medium, showsColors: false)
        #expect(bar.frame.width < fullWidth)
    }

    @Test func overlayViewStartsWithRememberedStyleAndNothingToCancel() throws {
        let defaults = makeDefaults()
        AnnotationSettings(defaults: defaults).color = .green
        AnnotationSettings(defaults: defaults).size = .large
        let view = OverlayView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 300), windows: [],
            snapshotImage: try whiteImage(), imageScale: 0.1,
            annotationSettings: AnnotationSettings(defaults: defaults)
        )

        #expect(view.annotation.color == .green)
        #expect(view.annotation.size == .large)
        #expect(view.annotations.isEmpty)
        #expect(view.handleCancel())          // 没有选区、没有工具：没东西可取消 → 由控制器退出截图
        view.undo()                           // 空状态下撤销 / 重做 / 提交文字都不应崩溃
        view.redo()
        view.commitPendingText()
        view.resetSelection()
        #expect(!view.model.isLocked)
    }
}
