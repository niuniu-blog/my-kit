import Foundation

/// 九种标注工具。allCases 的顺序就是工具条上从左到右的顺序。
public enum AnnotationTool: String, CaseIterable, Equatable, Sendable {
    case rectangle, ellipse, arrow, line, pen, highlighter, text, mosaic, number

    /// 鼠标悬停在按钮上时显示的中文名
    public var displayName: String {
        switch self {
        case .rectangle: return "方框"
        case .ellipse: return "椭圆"
        case .arrow: return "箭头"
        case .line: return "直线"
        case .pen: return "画笔"
        case .highlighter: return "荧光笔"
        case .text: return "文字"
        case .mosaic: return "马赛克"
        case .number: return "序号"
        }
    }

    /// 按钮图标（SF Symbols）
    public var symbolName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .pen: return "pencil"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .mosaic: return "checkerboard.rectangle"
        case .number: return "1.circle"
        }
    }

    /// 马赛克没有颜色可选：选中它时样式栏只显示粗细（= 方块大小）
    public var usesColor: Bool {
        self != .mosaic
    }
}
