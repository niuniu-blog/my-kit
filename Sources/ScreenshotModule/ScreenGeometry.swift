import CoreGraphics

/// 坐标系换算。截图遮罩内部统一用"屏内坐标"：某块屏幕的左上角为原点、y 向下、单位 pt。
public enum ScreenGeometry {
    /// 屏内坐标 → AppKit 全局坐标（主屏左下角为原点、y 向上）。screenFrame 是 NSScreen.frame。
    public static func appKitRect(fromLocal rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + rect.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
