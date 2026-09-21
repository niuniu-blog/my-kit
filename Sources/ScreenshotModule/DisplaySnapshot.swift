import CoreGraphics

/// 一块显示器的描述（在主线程从 NSScreen 读出，之后可以带到后台线程用）。
public struct ScreenDescriptor: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    /// AppKit 全局坐标（主屏左下角为原点、y 向上），即 NSScreen.frame
    public let frame: CGRect
    /// CG 全局坐标（主屏左上角为原点、y 向下），即 CGDisplayBounds
    public let cgBounds: CGRect
    /// 像素倍数，Retina 为 2
    public let scale: CGFloat

    public init(displayID: CGDirectDisplayID, frame: CGRect, cgBounds: CGRect, scale: CGFloat) {
        self.displayID = displayID
        self.frame = frame
        self.cgBounds = cgBounds
        self.scale = scale
    }
}

/// 一块显示器的定格画面。CGImage 创建后不可变，跨线程传递是安全的。
public struct DisplaySnapshot: @unchecked Sendable {
    public let screen: ScreenDescriptor
    public let image: CGImage

    public init(screen: ScreenDescriptor, image: CGImage) {
        self.screen = screen
        self.image = image
    }

    /// 这块屏的屏内坐标范围：(0, 0, 宽, 高)，单位 pt
    public var localBounds: CGRect {
        CGRect(origin: .zero, size: screen.frame.size)
    }

    /// 图像像素与 pt 的实际比例（以图像为准，比 screen.scale 更可靠）
    public var imageScale: CGFloat {
        screen.frame.width > 0 ? CGFloat(image.width) / screen.frame.width : screen.scale
    }
}

/// 一次截图的成品。
public struct CaptureResult {
    public let image: CGImage
    /// 图片的 pt 尺寸（= 选区大小）
    public let pointSize: CGSize
    /// 选区在屏幕上的位置，AppKit 全局坐标 —— 贴图窗口直接用它当 frame
    public let screenRect: CGRect

    /// 按选区（屏内坐标）从定格画面裁出成品。选区无效时返回 nil。
    public static func make(selection: CGRect, snapshot: DisplaySnapshot) -> CaptureResult? {
        guard let image = ImageCropper.crop(snapshot.image, rect: selection, scale: snapshot.imageScale) else { return nil }
        return CaptureResult(
            image: image,
            pointSize: selection.size,
            screenRect: ScreenGeometry.appKitRect(fromLocal: selection, screenFrame: snapshot.screen.frame)
        )
    }
}
