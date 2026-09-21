import CoreGraphics

public enum ImageCropper {
    /// 按选区从定格的整屏图像里裁剪。
    /// rect 是屏内坐标（左上角原点、pt）；scale 是这块屏的像素倍数（Retina 为 2）。
    /// CGImage 的像素坐标同样以左上角为原点，所以只需要乘以 scale、取整、裁到图像范围内。
    public static func crop(_ image: CGImage, rect: CGRect, scale: CGFloat) -> CGImage? {
        let pixelRect = CGRect(
            x: (rect.minX * scale).rounded(),
            y: (rect.minY * scale).rounded(),
            width: (rect.width * scale).rounded(),
            height: (rect.height * scale).rounded()
        )
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = pixelRect.intersection(imageBounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        return image.cropping(to: clipped)
    }
}
