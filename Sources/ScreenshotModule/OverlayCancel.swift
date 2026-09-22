import Foundation

/// 右键（逐级取消）要做的事，按优先级从高到低。
enum CancelLevel: Equatable {
    /// 正在输入文字 → 完成文字输入
    case finishText
    /// 有工具选中 → 取消选中工具
    case deselectTool
    /// 有选区 → 清除选区（连同全部标注和重做栈），回到窗口识别状态
    case clearSelection
    /// 什么都没有 → 退出截图
    case exitCapture
}

/// 取消的规则。纯函数。
enum OverlayCancel {
    /// Esc：按一下就退出截图。唯一的例外是正在往标注里打字 —— 这时 Esc 只完成输入，
    /// 否则刚打的字会连同整张截图一起丢掉。
    static func escapeLevel(isEditingText: Bool) -> CancelLevel {
        isEditingText ? .finishText : .exitCapture
    }

    /// 右键 / 工具条 ✕：每按一次退一级。
    static func level(isEditingText: Bool, hasTool: Bool, hasSelection: Bool) -> CancelLevel {
        if isEditingText { return .finishText }
        if hasTool { return .deselectTool }
        if hasSelection { return .clearSelection }
        return .exitCapture
    }
}
