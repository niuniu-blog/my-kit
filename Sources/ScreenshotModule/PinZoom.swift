import CoreGraphics

/// 贴图的缩放：滚轮 / 双指滑动，以及触控板双指捏合。纯函数。
public enum PinZoom {
    public static let range: ClosedRange<CGFloat> = 0.1...5.0
    /// 滚轮每 1 个单位改变 1%
    public static let sensitivity: CGFloat = 0.01

    /// 向上滚（deltaY > 0）放大，向下滚缩小；结果夹在 10%…500%。
    public static func scale(current: CGFloat, scrollDeltaY: CGFloat) -> CGFloat {
        let next = current * (1 + scrollDeltaY * sensitivity)
        return min(max(next, range.lowerBound), range.upperBound)
    }

    /// 触控板双指捏合。magnification 是系统给出的"这一小步放大了多少"（张开为正、捏拢为负），
    /// 相对当前大小生效；结果同样夹在 10%…500%。
    public static func scale(current: CGFloat, magnification: CGFloat) -> CGFloat {
        let factor = max(1 + magnification, 0)      // 异常的大负值不能让图片翻转或变成 0
        let next = current * factor
        return min(max(next, range.lowerBound), range.upperBound)
    }

    /// 以窗口中心为锚点，算出缩放后的窗口 frame。baseSize 是 100% 时的大小。
    public static func frame(current: CGRect, baseSize: CGSize, scale: CGFloat) -> CGRect {
        let size = CGSize(width: (baseSize.width * scale).rounded(), height: (baseSize.height * scale).rounded())
        return CGRect(
            x: (current.midX - size.width / 2).rounded(),
            y: (current.midY - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }
}
