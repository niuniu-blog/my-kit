import CoreGraphics

/// 把 CGEvent 的原始字段翻译成 DoubleTapDetector 的事件。纯函数，方便测试。
public enum ModifierEventTranslator {
    /// target：要检测双击的那个修饰键（默认 Option，可在偏好设置里改）。
    /// Caps Lock（maskAlphaShift）可能长期亮着，不算"其他修饰键"。
    public static func translate(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags,
        target: DoubleTapModifier = .option
    ) -> DoubleTapDetector.Event? {
        switch type {
        case .keyDown:
            return .otherInput
        case .flagsChanged:
            guard target.keyCodes.contains(keyCode) else { return .otherInput }
            if flags.contains(target.mask) {
                let others = KeyCombo.relevantModifiers.subtracting(target.mask)
                return .targetDown(otherModifiersHeld: !flags.intersection(others).isEmpty)
            }
            return .targetUp
        default:
            return nil
        }
    }
}
