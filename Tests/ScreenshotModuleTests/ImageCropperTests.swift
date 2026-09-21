import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct ImageCropperTests {
    /// 200×100 像素：**上半部分红色、下半部分蓝色**（以图像左上角为原点描述）。
    private func makeImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // CGContext 的坐标原点在左下角：y 50…100 是图像的上半部分
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 50, width: 200, height: 50))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 50))
        return try #require(context.makeImage())
    }

    /// 取图像正中间那个像素的 (r, g, b)。
    private func centerPixel(of image: CGImage) throws -> [UInt8] {
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // 把图像平移，使其中心落在这个 1×1 的画布上
        context.draw(image, in: CGRect(
            x: -CGFloat(image.width) / 2 + 0.5, y: -CGFloat(image.height) / 2 + 0.5,
            width: CGFloat(image.width), height: CGFloat(image.height)
        ))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return [data[0], data[1], data[2]]
    }

    @Test func cropsInPixelsAtScaleOne() throws {
        let cropped = try #require(ImageCropper.crop(try makeImage(), rect: CGRect(x: 10, y: 5, width: 60, height: 30), scale: 1))
        #expect(cropped.width == 60)
        #expect(cropped.height == 30)
    }

    @Test func multipliesByScaleOnRetina() throws {
        let cropped = try #require(ImageCropper.crop(try makeImage(), rect: CGRect(x: 10, y: 5, width: 60, height: 30), scale: 2))
        #expect(cropped.width == 120)
        #expect(cropped.height == 60)
    }

    @Test func rectUsesTopLeftOrigin() throws {
        let image = try makeImage()
        let top = try #require(ImageCropper.crop(image, rect: CGRect(x: 0, y: 0, width: 200, height: 40), scale: 1))
        let bottom = try #require(ImageCropper.crop(image, rect: CGRect(x: 0, y: 60, width: 200, height: 40), scale: 1))

        let topColor = try centerPixel(of: top)
        let bottomColor = try centerPixel(of: bottom)
        // 颜色经过色彩空间换算后不是精确的 255/0，只判断主色
        #expect(topColor[0] > 200 && topColor[2] < 60)          // 上面是红色
        #expect(bottomColor[2] > 200 && bottomColor[0] < 60)    // 下面是蓝色
    }

    @Test func clipsToImageBounds() throws {
        let cropped = try #require(ImageCropper.crop(try makeImage(), rect: CGRect(x: 150, y: 80, width: 500, height: 500), scale: 1))
        #expect(cropped.width == 50)
        #expect(cropped.height == 20)
    }

    @Test func returnsNilWhenRectIsOutsideOrEmpty() throws {
        let image = try makeImage()
        #expect(ImageCropper.crop(image, rect: CGRect(x: 500, y: 500, width: 10, height: 10), scale: 1) == nil)
        #expect(ImageCropper.crop(image, rect: CGRect(x: 10, y: 10, width: 0, height: 0), scale: 1) == nil)
    }
}
