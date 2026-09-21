import CoreGraphics

/// 贴图的滚轮缩放。纯函数。
public enum PinZoom {
    public static let range: ClosedRange<CGFloat> = 0.1...5.0
    /// 滚轮每 1 个单位改变 1%
    public static let sensitivity: CGFloat = 0.01

    /// 向上滚（deltaY > 0）放大，向下滚缩小；结果夹在 10%…500%。
    public static func scale(current: CGFloat, scrollDeltaY: CGFloat) -> CGFloat {
        let next = current * (1 + scrollDeltaY * sensitivity)
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
