import CoreGraphics

/// 6 种预设颜色。
public enum AnnotationColor: String, CaseIterable, Equatable, Sendable {
    case red, yellow, green, blue, black, white

    public var displayName: String {
        switch self {
        case .red: return "红"
        case .yellow: return "黄"
        case .green: return "绿"
        case .blue: return "蓝"
        case .black: return "黑"
        case .white: return "白"
        }
    }

    /// 0…1 的 RGB 分量
    public var components: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        switch self {
        case .red: return (1.0, 0.23, 0.19)
        case .yellow: return (1.0, 0.8, 0.0)
        case .green: return (0.2, 0.78, 0.35)
        case .blue: return (0.0, 0.48, 1.0)
        case .black: return (0.0, 0.0, 0.0)
        case .white: return (1.0, 1.0, 1.0)
        }
    }

    public func cgColor(alpha: CGFloat = 1) -> CGColor {
        let rgb = components
        return CGColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    }

    /// 序号圆里的数字：底色浅（白、黄）时用黑字，其余用白字
    public var numberTextIsBlack: Bool {
        self == .white || self == .yellow
    }
}

/// 3 档粗细。同一个档位在不同工具上的含义不同。
public enum AnnotationSize: String, CaseIterable, Equatable, Sendable {
    case small, medium, large

    public var displayName: String {
        switch self {
        case .small: return "细"
        case .medium: return "中"
        case .large: return "粗"
        }
    }

    /// 方框 / 椭圆 / 直线 / 箭头 / 画笔的线宽（pt）
    public var strokeWidth: CGFloat {
        switch self {
        case .small: return 2
        case .medium: return 4
        case .large: return 6
        }
    }

    /// 荧光笔的线宽（pt）
    public var highlighterWidth: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 18
        case .large: return 24
        }
    }

    /// 文字的字号（pt）
    public var fontSize: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 20
        case .large: return 28
        }
    }

    /// 马赛克方块的边长（pt）
    public var mosaicBlock: CGFloat {
        switch self {
        case .small: return 8
        case .medium: return 12
        case .large: return 18
        }
    }

    /// 序号圆的直径（pt）
    public var numberDiameter: CGFloat {
        switch self {
        case .small: return 22
        case .medium: return 28
        case .large: return 36
        }
    }
}

/// 荧光笔的不透明度
public let annotationHighlighterAlpha: CGFloat = 0.4
