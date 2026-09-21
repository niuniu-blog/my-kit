import AppKit
import Testing
@testable import Core

@Suite struct ImageEncodingTests {
    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @Test func pngKeepsPixelSizeAndRecordsPointSize() throws {
        let image = try makeImage(width: 200, height: 100)

        let data = try #require(ImageEncoding.pngData(from: image, pointSize: CGSize(width: 100, height: 50)))
        let decoded = try #require(NSBitmapImageRep(data: data))

        #expect(decoded.pixelsWide == 200)
        #expect(decoded.pixelsHigh == 100)
        #expect(abs(decoded.size.width - 100) < 0.5)    // 144 DPI → 按 pt 尺寸显示
        #expect(abs(decoded.size.height - 50) < 0.5)
    }

    @Test func zeroPointSizeFallsBackToPixelSize() throws {
        let image = try makeImage(width: 30, height: 20)
        let data = try #require(ImageEncoding.pngData(from: image, pointSize: .zero))
        let decoded = try #require(NSBitmapImageRep(data: data))
        #expect(decoded.pixelsWide == 30)
        #expect(decoded.pixelsHigh == 20)
    }

    @Test func tiffIsProduced() throws {
        let image = try makeImage(width: 10, height: 10)
        #expect(ImageEncoding.tiffData(from: image, pointSize: CGSize(width: 10, height: 10)) != nil)
    }
}
