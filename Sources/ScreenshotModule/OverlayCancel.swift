import Foundation

/// Esc / 右键要做的事，按优先级从高到低。
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

/// 取消键的层级。纯函数。
enum OverlayCancel {
    static func level(isEditingText: Bool, hasTool: Bool, hasSelection: Bool) -> CancelLevel {
        if isEditingText { return .finishText }
        if hasTool { return .deselectTool }
        if hasSelection { return .clearSelection }
        return .exitCapture
    }
}
