import CoreGraphics

/// 一个标注。几何数据用"选区内坐标"：选区左上角为原点、y 向下、单位 pt。
/// 只是一小段数据：屏幕上实时绘制，导出时再合成到图上；撤销 = 去掉最后一条。
public struct Annotation: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case rectangle(CGRect)
        case ellipse(CGRect)
        case line(from: CGPoint, to: CGPoint)
        case arrow(from: CGPoint, to: CGPoint)
        case pen([CGPoint])
        case highlighter([CGPoint])
        /// origin 是文字左上角
        case text(String, origin: CGPoint)
        case mosaic(CGRect)
        case number(Int, center: CGPoint)
    }

    public let kind: Kind
    public let color: AnnotationColor
    public let size: AnnotationSize

    public init(kind: Kind, color: AnnotationColor, size: AnnotationSize) {
        self.kind = kind
        self.color = color
        self.size = size
    }

    public var isMosaic: Bool {
        if case .mosaic = kind { return true }
        return false
    }

    public var isNumber: Bool {
        if case .number = kind { return true }
        return false
    }
}
