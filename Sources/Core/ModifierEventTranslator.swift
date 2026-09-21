import CoreGraphics

/// 把 CGEvent 的原始字段翻译成 DoubleTapDetector 的事件。纯函数，方便测试。
public enum ModifierEventTranslator {
    /// 左 Option = 58，右 Option = 61
    public static let optionKeyCodes: Set<Int64> = [58, 61]
    /// Caps Lock（maskAlphaShift）可能长期亮着，不算"其他修饰键"
    private static let otherModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskShift]

    public static func translate(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> DoubleTapDetector.Event? {
        switch type {
        case .keyDown:
            return .otherInput
        case .flagsChanged:
            guard optionKeyCodes.contains(keyCode) else { return .otherInput }
            if flags.contains(.maskAlternate) {
                return .targetDown(otherModifiersHeld: !flags.intersection(otherModifiers).isEmpty)
            }
            return .targetUp
        default:
            return nil
        }
    }
}
