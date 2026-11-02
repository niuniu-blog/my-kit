import AppKit
import Testing
@testable import Core

@Suite struct EditShortcutsTests {
    @Test func mapsCommandKeysToEditActions() {
        #expect(EditShortcuts.action(characters: "c", modifiers: .command) == #selector(NSText.copy(_:)))
        #expect(EditShortcuts.action(characters: "v", modifiers: .command) == #selector(NSText.paste(_:)))
        #expect(EditShortcuts.action(characters: "x", modifiers: .command) == #selector(NSText.cut(_:)))
        #expect(EditShortcuts.action(characters: "a", modifiers: .command) == #selector(NSText.selectAll(_:)))
        #expect(EditShortcuts.action(characters: "z", modifiers: .command) == Selector(("undo:")))
        #expect(EditShortcuts.action(characters: "z", modifiers: [.command, .shift]) == Selector(("redo:")))
        #expect(EditShortcuts.action(characters: "c", modifiers: [.command, .capsLock]) == #selector(NSText.copy(_:)))
    }

    @Test func ignoresOtherCombos() {
        #expect(EditShortcuts.action(characters: "c", modifiers: []) == nil)
        #expect(EditShortcuts.action(characters: "c", modifiers: [.command, .option]) == nil)
        #expect(EditShortcuts.action(characters: "v", modifiers: [.command, .shift]) == nil)
        #expect(EditShortcuts.action(characters: "w", modifiers: .command) == nil)
    }
}
