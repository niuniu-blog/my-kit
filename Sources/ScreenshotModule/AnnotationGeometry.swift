import CoreGraphics
import Foundation

/// 标注用到的几何计算。纯函数。
public enum AnnotationGeometry {
    public static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    /// 由拖动的起点和当前点得到矩形。square = true（按住 Shift）时取较长的一边做正方形，方向跟随拖动方向。
    public static func rect(from start: CGPoint, to current: CGPoint, square: Bool) -> CGRect {
        var dx = current.x - start.x
        var dy = current.y - start.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        return CGRect(x: min(start.x, start.x + dx), y: min(start.y, start.y + dy), width: abs(dx), height: abs(dy))
    }

    /// 按住 Shift 画直线 / 箭头：方向吸附到最近的 45° 倍数，长度不变。
    public static func snappedEndpoint(from start: CGPoint, to current: CGPoint) -> CGPoint {
        let length = distance(start, current)
        guard length > 0 else { return current }
        let step = CGFloat.pi / 4
        let angle = (atan2(current.y - start.y, current.x - start.x) / step).rounded() * step
        return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
    }

    /// 箭头头部的长度：线宽 × 4 + 6
    public static func arrowHeadLength(lineWidth: CGFloat) -> CGFloat {
        lineWidth * 4 + 6
    }

    /// 箭头头部三角形的三个顶点：[尖端, 左翼, 右翼]。两翼与箭身夹角 ±28°。
    public static func arrowHead(from start: CGPoint, to tip: CGPoint, lineWidth: CGFloat) -> [CGPoint] {
        let length = arrowHeadLength(lineWidth: lineWidth)
        let angle = atan2(tip.y - start.y, tip.x - start.x)
        let spread = CGFloat(28) * .pi / 180
        let left = CGPoint(x: tip.x - cos(angle - spread) * length, y: tip.y - sin(angle - spread) * length)
        let right = CGPoint(x: tip.x - cos(angle + spread) * length, y: tip.y - sin(angle + spread) * length)
        return [tip, left, right]
    }

    /// 箭身画到哪里为止：停在头部三角形的底边附近，免得粗线从尖端两侧露出来。
    public static func arrowShaftEnd(from start: CGPoint, to tip: CGPoint, lineWidth: CGFloat) -> CGPoint {
        let total = distance(start, tip)
        let inset = arrowHeadLength(lineWidth: lineWidth) * cos(CGFloat(28) * .pi / 180) * 0.9
        guard total > inset else { return start }
        let ratio = (total - inset) / total
        return CGPoint(x: start.x + (tip.x - start.x) * ratio, y: start.y + (tip.y - start.y) * ratio)
    }
}
