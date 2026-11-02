import AppKit

/// MyKit 没有主菜单（菜单栏软件），输入框里的 ⌘X / ⌘C / ⌘V / ⌘A / ⌘Z / ⇧⌘Z 没人接，要自己转发给当前输入框。
@MainActor
public enum EditShortcuts {
    /// 是编辑快捷键并且有输入框接住了就返回 true
    public static func perform(_ event: NSEvent, from sender: Any?) -> Bool {
        guard let action = action(for: event) else { return false }
        return NSApp.sendAction(action, to: nil, from: sender)
    }

    public nonisolated static func action(for event: NSEvent) -> Selector? {
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        return action(characters: characters, modifiers: event.modifierFlags)
    }

    public nonisolated static func action(characters: String, modifiers: NSEvent.ModifierFlags) -> Selector? {
        switch modifiers.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) {
        case .command:
            switch characters {
            case "x": return #selector(NSText.cut(_:))
            case "c": return #selector(NSText.copy(_:))
            case "v": return #selector(NSText.paste(_:))
            case "a": return #selector(NSText.selectAll(_:))
            case "z": return Selector(("undo:"))
            default: return nil
            }
        case [.command, .shift]:
            return characters == "z" ? Selector(("redo:")) : nil
        default:
            return nil
        }
    }
}

/// 输入框里能用 ⌘C / ⌘V 等编辑快捷键的普通窗口。有输入框的窗口都用它代替 NSWindow。
open class EditableWindow: NSWindow {
    open override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if EditShortcuts.perform(event, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}
