import Testing
@testable import ScreenshotModule

@Suite struct OverlayCancelTests {
    // Esc：除了"正在打字"这一种情况，一律直接退出截图

    @Test func escapeExitsEvenWithAToolAndASelection() {
        #expect(OverlayCancel.escapeLevel(isEditingText: false) == .exitCapture)
    }

    @Test func escapeWhileTypingOnlyFinishesTheText() {
        // 正在往标注里打字时按 Esc = 完成输入（不然刚打的字连同整张截图一起没了）
        #expect(OverlayCancel.escapeLevel(isEditingText: true) == .finishText)
    }

    // 右键 / 工具条 ✕：逐级取消

    @Test func finishingTextComesFirst() {
        #expect(OverlayCancel.level(isEditingText: true, hasTool: true, hasSelection: true) == .finishText)
    }

    @Test func thenDeselectingTheTool() {
        #expect(OverlayCancel.level(isEditingText: false, hasTool: true, hasSelection: true) == .deselectTool)
    }

    @Test func thenClearingTheSelection() {
        #expect(OverlayCancel.level(isEditingText: false, hasTool: false, hasSelection: true) == .clearSelection)
    }

    @Test func finallyExitingTheCapture() {
        #expect(OverlayCancel.level(isEditingText: false, hasTool: false, hasSelection: false) == .exitCapture)
    }
}
