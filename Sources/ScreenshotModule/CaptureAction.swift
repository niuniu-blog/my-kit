import AppKit

/// 选好区域之后可以做的四件事。
public enum CaptureAction: Equatable, CaseIterable {
    case pin, recognize, save, copy
}

/// 遮罩上的一次"指令"：来自键盘、工具条按钮、右键或双击。
enum OverlayCommand: Equatable {
    case cancel
    case perform(CaptureAction)
    /// 撤销 / 重做最后一个标注
    case undo
    case redo
}

/// 键盘 → 指令。纯函数。
enum OverlayKeyMap {
    static func command(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) -> OverlayCommand? {
        let relevant = modifiers.intersection([.command, .option, .control, .shift])
        if keyCode == 53 { return .cancel }                                   // Esc
        if relevant.isEmpty, keyCode == 36 || keyCode == 76 {                 // 回车 / 小键盘回车
            return .perform(.copy)
        }
        guard let key = characters?.lowercased() else { return nil }
        if relevant == [.command, .shift], key == "z" { return .redo }       // ⇧⌘Z
        guard relevant == .command else { return nil }
        switch key {
        case "z": return .undo
        case "c": return .perform(.copy)
        case "s": return .perform(.save)
        case "r": return .perform(.recognize)
        case "t": return .perform(.pin)
        default: return nil
        }
    }
}
