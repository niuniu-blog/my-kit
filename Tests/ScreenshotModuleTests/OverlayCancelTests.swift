import Testing
@testable import ScreenshotModule

@Suite struct OverlayCancelTests {
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
