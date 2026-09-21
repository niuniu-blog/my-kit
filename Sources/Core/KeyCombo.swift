import AppKit
import CoreGraphics

/// 一个全局组合键，例如 ⇧⌘A。
public struct KeyCombo: Equatable {
    /// 虚拟键码（与键盘布局无关），A = 0
    public let keyCode: Int64
    /// 只使用 ⌘ ⌃ ⌥ ⇧ 四个修饰键
    public let modifiers: CGEventFlags

    public init(keyCode: Int64, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⇧⌘A —— 截图的默认快捷键
    public static let shiftCommandA = KeyCombo(keyCode: 0, modifiers: [.maskShift, .maskCommand])

    /// 参与比较的四个修饰键；Caps Lock、fn 等一律忽略
    public static let relevantModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    /// 按 macOS 的习惯顺序 ⌃⌥⇧⌘ 拼出显示文字，例如 "⇧⌘A"
    public func displayString(keyLabel: String) -> String {
        var text = ""
        if modifiers.contains(.maskControl) { text += "⌃" }
        if modifiers.contains(.maskAlternate) { text += "⌥" }
        if modifiers.contains(.maskShift) { text += "⇧" }
        if modifiers.contains(.maskCommand) { text += "⌘" }
        return text + keyLabel
    }

    /// AppKit 的修饰键 → 事件监听用的修饰键（只保留 ⌘⌃⌥⇧）
    public static func modifiers(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.control) { result.insert(.maskControl) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        return result
    }

    /// 反向换算，用于在菜单项上显示快捷键
    public var appKitModifiers: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if modifiers.contains(.maskCommand) { result.insert(.command) }
        if modifiers.contains(.maskControl) { result.insert(.control) }
        if modifiers.contains(.maskAlternate) { result.insert(.option) }
        if modifiers.contains(.maskShift) { result.insert(.shift) }
        return result
    }
}

/// 判断一个键盘事件是否正好是某个组合键。纯函数。
public enum KeyComboMatcher {
    /// 修饰键必须**完全相等**：多按或少按一个 ⌘⌃⌥⇧ 都不算；Caps Lock、fn 等不参与比较。
    public static func matches(_ combo: KeyCombo, type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard type == .keyDown, keyCode == combo.keyCode else { return false }
        return flags.intersection(KeyCombo.relevantModifiers) == combo.modifiers
    }
}
