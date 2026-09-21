import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct AnnotationRendererTests {
    struct RGBA: Equatable {
        let red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8

        var isReddish: Bool { red > 200 && green < 110 && blue < 110 }
        var isWhite: Bool { red > 250 && green > 250 && blue > 250 }
    }

    /// 把图片读成像素数组。x、y 以左上角为原点。
    private struct Bitmap {
        let width: Int
        let height: Int
        private let bytes: [UInt8]
        private let bytesPerRow: Int

        init(_ image: CGImage) throws {
            let context = try #require(CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let data = try #require(context.data)
            width = image.width
            height = image.height
            bytesPerRow = context.bytesPerRow
            bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: bytesPerRow * image.height))
        }

        func pixel(_ x: Int, _ y: Int) -> RGBA {
            let offset = y * bytesPerRow + x * 4
            return RGBA(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2], alpha: bytes[offset + 3])
        }
    }

    private func makeContext(width: Int, height: Int) throws -> CGContext {
        try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
    }

    /// 纯白底图
    private func whiteImage(width: Int, height: Int) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    /// 每 2 像素一条竖条纹、左半偏红右半偏蓝的底图：相邻像素颜色不同，方便看出马赛克是否生效
    private func stripedImage(width: Int, height: Int) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        for x in 0..<width {
            let bright: CGFloat = (x / 2) % 2 == 0 ? 1.0 : 0.2
            let color = x < width / 2
                ? CGColor(srgbRed: bright, green: 0.1, blue: 0.1, alpha: 1)
                : CGColor(srgbRed: 0.1, green: 0.1, blue: bright, alpha: 1)
            context.setFillColor(color)
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return try #require(context.makeImage())
    }

    private func rectangle(_ rect: CGRect) -> Annotation {
        Annotation(kind: .rectangle(rect), color: .red, size: .medium)
    }

    // MARK: flatten

    @Test func noAnnotationsReturnsTheBaseImageItself() throws {
        let base = try whiteImage(width: 100, height: 60)
        let output = try #require(AnnotationRenderer.flatten(base: base, items: [], pointSize: CGSize(width: 100, height: 60)))
        #expect(output === base)
    }

    @Test func rectangleStrokesTheEdgeAndLeavesTheInteriorUntouched() throws {
        let base = try whiteImage(width: 100, height: 60)
        let output = try #require(AnnotationRenderer.flatten(
            base: base, items: [rectangle(CGRect(x: 20, y: 10, width: 40, height: 30))], pointSize: CGSize(width: 100, height: 60)))
        let bitmap = try Bitmap(output)

        #expect(bitmap.width == 100)
        #expect(bitmap.height == 60)
        #expect(bitmap.pixel(20, 25).isReddish)        // 左边
        #expect(bitmap.pixel(40, 10).isReddish)        // 上边（y 向下：上边在 y = 10）
        #expect(bitmap.pixel(40, 39).isReddish)        // 下边
        #expect(bitmap.pixel(40, 25).isWhite)          // 内部
        #expect(bitmap.pixel(5, 5).isWhite)            // 外部
        #expect(bitmap.pixel(40, 50).isWhite)          // 如果 y 方向画反了，这里会是红的
    }

    @Test func retinaOutputKeepsPixelSizeAndScalesGeometry() throws {
        let base = try whiteImage(width: 200, height: 120)      // 100×60 pt 的 2× 图
        let output = try #require(AnnotationRenderer.flatten(
            base: base, items: [rectangle(CGRect(x: 20, y: 10, width: 40, height: 30))], pointSize: CGSize(width: 100, height: 60)))
        let bitmap = try Bitmap(output)

        #expect(bitmap.width == 200)
        #expect(bitmap.height == 120)
        #expect(bitmap.pixel(40, 50).isReddish)        // (20, 25) pt → (40, 50) px
        #expect(bitmap.pixel(80, 50).isWhite)
    }

    @Test func mosaicMakesBlocksUniformAndLeavesTheRestUntouched() throws {
        let base = try stripedImage(width: 120, height: 60)
        let original = try Bitmap(base)
        let mosaic = Annotation(kind: .mosaic(CGRect(x: 24, y: 12, width: 48, height: 24)), color: .red, size: .medium)   // 方块 12pt
        let output = try #require(AnnotationRenderer.flatten(base: base, items: [mosaic], pointSize: CGSize(width: 120, height: 60)))
        let bitmap = try Bitmap(output)

        // 原图里这两个点颜色不同；马赛克后它们在同一个方块里，颜色一致
        #expect(original.pixel(25, 13) != original.pixel(27, 13))
        #expect(bitmap.pixel(25, 13) == bitmap.pixel(27, 13))
        #expect(bitmap.pixel(25, 13) == bitmap.pixel(34, 22))
        // 不同方块可以不同：最左一块（偏红区）和最右一块（偏蓝区）
        #expect(bitmap.pixel(30, 18) != bitmap.pixel(66, 18))
        // 马赛克区域之外保持原样
        #expect(bitmap.pixel(10, 5) == original.pixel(10, 5))
        #expect(bitmap.pixel(100, 50) == original.pixel(100, 50))
    }

    @Test func onlyMosaicSkipsEverythingElse() throws {
        let base = try stripedImage(width: 120, height: 60)
        let original = try Bitmap(base)
        let items = [
            rectangle(CGRect(x: 80, y: 10, width: 30, height: 30)),
            Annotation(kind: .mosaic(CGRect(x: 24, y: 12, width: 48, height: 24)), color: .red, size: .medium),
        ]
        let output = try #require(AnnotationRenderer.flatten(
            base: base, items: items, pointSize: CGSize(width: 120, height: 60), onlyMosaic: true))
        let bitmap = try Bitmap(output)

        #expect(bitmap.pixel(80, 25) == original.pixel(80, 25))      // 方框没有画上去
        #expect(bitmap.pixel(25, 13) == bitmap.pixel(27, 13))        // 马赛克生效
    }

    @Test func onlyMosaicWithoutAnyMosaicReturnsTheBase() throws {
        let base = try whiteImage(width: 50, height: 50)
        let output = try #require(AnnotationRenderer.flatten(
            base: base, items: [rectangle(CGRect(x: 5, y: 5, width: 20, height: 20))],
            pointSize: CGSize(width: 50, height: 50), onlyMosaic: true))
        #expect(output === base)
    }

    @Test func everyKindRendersWithoutCrashingAndChangesPixels() throws {
        let base = try whiteImage(width: 200, height: 150)
        let size = CGSize(width: 200, height: 150)
        let kinds: [Annotation.Kind] = [
            .ellipse(CGRect(x: 10, y: 10, width: 60, height: 40)),
            .line(from: CGPoint(x: 10, y: 70), to: CGPoint(x: 90, y: 70)),
            .arrow(from: CGPoint(x: 10, y: 90), to: CGPoint(x: 90, y: 90)),
            .pen([CGPoint(x: 100, y: 10), CGPoint(x: 120, y: 30), CGPoint(x: 140, y: 10)]),
            .highlighter([CGPoint(x: 100, y: 60), CGPoint(x: 180, y: 60)]),
            .text("标注 Text", origin: CGPoint(x: 100, y: 80)),
            .number(3, center: CGPoint(x: 40, y: 125)),
        ]
        for kind in kinds {
            let output = try #require(AnnotationRenderer.flatten(
                base: base, items: [Annotation(kind: kind, color: .blue, size: .medium)], pointSize: size))
            let bitmap = try Bitmap(output)
            var changed = 0
            for y in stride(from: 0, to: 150, by: 2) {
                for x in stride(from: 0, to: 200, by: 2) where !bitmap.pixel(x, y).isWhite {
                    changed += 1
                }
            }
            #expect(changed > 0, "\(kind)")
        }
    }

    @Test func highlighterIsTranslucent() throws {
        let base = try whiteImage(width: 100, height: 60)
        let item = Annotation(kind: .highlighter([CGPoint(x: 10, y: 30), CGPoint(x: 90, y: 30)]), color: .black, size: .medium)
        let output = try #require(AnnotationRenderer.flatten(base: base, items: [item], pointSize: CGSize(width: 100, height: 60)))
        let pixel = try Bitmap(output).pixel(50, 30)
        // 40% 的黑盖在白底上 ≈ 153：明显变暗，但远没有全黑
        #expect(pixel.red > 120)
        #expect(pixel.red < 190)
    }

    // MARK: draw（屏幕绘制路径）：裁剪到选区

    @Test func drawingIsClippedToTheSelection() throws {
        let context = try makeContext(width: 200, height: 100)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        // 模拟 OverlayView：左上角原点，再平移到选区原点 (50, 20)；选区 100×60
        context.translateBy(x: 0, y: 100)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 50, y: 20)
        let pen = Annotation(kind: .pen([CGPoint(x: 10, y: 30), CGPoint(x: 190, y: 30)]), color: .red, size: .medium)

        AnnotationRenderer.draw([pen], in: context, selectionSize: CGSize(width: 100, height: 60), baseImage: nil)

        let bitmap = try Bitmap(try #require(context.makeImage()))
        #expect(bitmap.pixel(100, 50).isReddish)       // 选区内 (50, 30)
        #expect(bitmap.pixel(170, 50).isWhite)         // 选区外 (120, 30)：被裁掉
    }

    @Test func mosaicCacheReusesTheImageForTheSameRect() throws {
        let cache = MosaicCache()
        let image = try whiteImage(width: 4, height: 4)
        var builds = 0
        let rect = CGRect(x: 1, y: 2, width: 30, height: 40)
        let first = cache.image(for: rect, block: 12) { builds += 1; return image }
        let second = cache.image(for: rect, block: 12) { builds += 1; return image }
        _ = cache.image(for: rect, block: 8) { builds += 1; return image }
        #expect(first === second)
        #expect(builds == 2)
        cache.removeAll()
        _ = cache.image(for: rect, block: 12) { builds += 1; return image }
        #expect(builds == 3)
    }
}
