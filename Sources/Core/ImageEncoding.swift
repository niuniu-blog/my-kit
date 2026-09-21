import AppKit

/// CGImage → PNG / TIFF 数据。pointSize 决定写入的 DPI：
/// Retina 屏上 200×100 像素、100×50 pt 的截图会标成 144 DPI，在"预览"里按 100×50 pt 显示。
public enum ImageEncoding {
    public static func pngData(from image: CGImage, pointSize: CGSize) -> Data? {
        bitmap(from: image, pointSize: pointSize).representation(using: .png, properties: [:])
    }

    public static func tiffData(from image: CGImage, pointSize: CGSize) -> Data? {
        bitmap(from: image, pointSize: pointSize).tiffRepresentation
    }

    private static func bitmap(from image: CGImage, pointSize: CGSize) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(cgImage: image)
        if pointSize.width > 0, pointSize.height > 0 {
            rep.size = pointSize
        }
        return rep
    }
}
