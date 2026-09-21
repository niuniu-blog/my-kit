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
    /// 复制 / 保存 / 贴图用：选区裁剪图 + 全部标注
    public let image: CGImage
    /// 文字识别 / 翻译用：选区裁剪图 + 仅马赛克（被遮住的内容不会被识别，箭头、方框等不干扰识别）
    public let ocrImage: CGImage
    /// 标注没能合成上去（位图上下文创建失败），image 退回成了不带标注的原图
    public let annotationsDropped: Bool
    /// 图片的 pt 尺寸（= 选区大小）
    public let pointSize: CGSize
    /// 选区在屏幕上的位置，AppKit 全局坐标 —— 贴图窗口直接用它当 frame
    public let screenRect: CGRect

    /// 按选区（屏内坐标）从定格画面裁出成品，并把标注（选区内坐标）合成上去。选区无效时返回 nil。
    public static func make(selection: CGRect, snapshot: DisplaySnapshot, annotations: [Annotation] = []) -> CaptureResult? {
        guard let cropped = ImageCropper.crop(snapshot.image, rect: selection, scale: snapshot.imageScale) else { return nil }
        let annotated = AnnotationRenderer.flatten(base: cropped, items: annotations, pointSize: selection.size)
        let forOCR = AnnotationRenderer.flatten(base: cropped, items: annotations, pointSize: selection.size, onlyMosaic: true)
        return CaptureResult(
            image: annotated ?? cropped,
            ocrImage: forOCR ?? cropped,
            annotationsDropped: annotated == nil,
            pointSize: selection.size,
            screenRect: ScreenGeometry.appKitRect(fromLocal: selection, screenFrame: snapshot.screen.frame)
        )
    }
}
