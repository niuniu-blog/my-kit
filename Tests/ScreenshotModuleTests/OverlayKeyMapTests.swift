import AppKit
import Testing
@testable import ScreenshotModule

@Suite struct OverlayKeyMapTests {
    @Test func escapeExitsRegardlessOfModifiers() {
        // 按一下 Esc 就退出截图（不是逐级取消；逐级取消是右键 / 工具条 ✕ 的事）
        #expect(OverlayKeyMap.command(keyCode: 53, characters: "\u{1b}", modifiers: []) == .exit)
        #expect(OverlayKeyMap.command(keyCode: 53, characters: "\u{1b}", modifiers: [.shift]) == .exit)
    }

    @Test func returnAndKeypadEnterCopy() {
        #expect(OverlayKeyMap.command(keyCode: 36, characters: "\r", modifiers: []) == .perform(.copy))
        #expect(OverlayKeyMap.command(keyCode: 76, characters: "\u{03}", modifiers: [.numericPad]) == .perform(.copy))
    }

    @Test func commandLettersMapToActions() {
        #expect(OverlayKeyMap.command(keyCode: 8, characters: "c", modifiers: [.command]) == .perform(.copy))
        #expect(OverlayKeyMap.command(keyCode: 1, characters: "s", modifiers: [.command]) == .perform(.save))
        #expect(OverlayKeyMap.command(keyCode: 15, characters: "r", modifiers: [.command]) == .perform(.recognize))
        #expect(OverlayKeyMap.command(keyCode: 17, characters: "t", modifiers: [.command]) == .perform(.pin))
    }

    @Test func capsLockDoesNotBreakShortcuts() {
        #expect(OverlayKeyMap.command(keyCode: 1, characters: "S", modifiers: [.command, .capsLock]) == .perform(.save))
    }

    @Test func lettersWithoutCommandOrWithExtraModifiersDoNothing() {
        #expect(OverlayKeyMap.command(keyCode: 1, characters: "s", modifiers: []) == nil)
        #expect(OverlayKeyMap.command(keyCode: 1, characters: "s", modifiers: [.command, .shift]) == nil)
        #expect(OverlayKeyMap.command(keyCode: 36, characters: "\r", modifiers: [.command]) == nil)
        #expect(OverlayKeyMap.command(keyCode: 0, characters: "a", modifiers: [.command]) == nil)
    }

    @Test func commandZUndoesAndShiftCommandZRedoes() {
        #expect(OverlayKeyMap.command(keyCode: 6, characters: "z", modifiers: [.command]) == .undo)
        #expect(OverlayKeyMap.command(keyCode: 6, characters: "z", modifiers: [.command, .shift]) == .redo)
        #expect(OverlayKeyMap.command(keyCode: 6, characters: "Z", modifiers: [.command, .shift, .capsLock]) == .redo)
        #expect(OverlayKeyMap.command(keyCode: 6, characters: "z", modifiers: []) == nil)
        #expect(OverlayKeyMap.command(keyCode: 6, characters: "z", modifiers: [.command, .option]) == nil)
    }
}
