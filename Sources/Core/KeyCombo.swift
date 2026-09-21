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

    /// ⇧⌘A —— 截图
    public static let shiftCommandA = KeyCombo(keyCode: 0, modifiers: [.maskShift, .maskCommand])
}

/// 判断一个键盘事件是否正好是某个组合键。纯函数。
public enum KeyComboMatcher {
    private static let relevantModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    /// 修饰键必须**完全相等**：多按或少按一个 ⌘⌃⌥⇧ 都不算；Caps Lock、fn 等不参与比较。
    public static func matches(_ combo: KeyCombo, type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard type == .keyDown, keyCode == combo.keyCode else { return false }
        return flags.intersection(relevantModifiers) == combo.modifiers
    }
}
