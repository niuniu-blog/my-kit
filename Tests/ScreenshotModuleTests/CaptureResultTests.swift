import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct CaptureResultTests {
    /// 一块 100×50 pt 的 2× 屏（图像 200×100 像素），位于主屏右侧。
    private func makeSnapshot() throws -> DisplaySnapshot {
        let context = try #require(CGContext(
            data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let screen = ScreenDescriptor(
            displayID: 7,
            frame: CGRect(x: 1600, y: 0, width: 100, height: 50),
            cgBounds: CGRect(x: 1600, y: 950, width: 100, height: 50),
            scale: 2
        )
        return DisplaySnapshot(screen: screen, image: image)
    }

    @Test func snapshotExposesLocalBoundsAndImageScale() throws {
        let snapshot = try makeSnapshot()
        #expect(snapshot.localBounds == CGRect(x: 0, y: 0, width: 100, height: 50))
        #expect(snapshot.imageScale == 2)
    }

    @Test func resultIsCroppedInPixelsAndPositionedInAppKitCoordinates() throws {
        let result = try #require(CaptureResult.make(
            selection: CGRect(x: 10, y: 5, width: 40, height: 20), snapshot: try makeSnapshot()
        ))

        #expect(result.image.width == 80)
        #expect(result.image.height == 40)
        #expect(result.pointSize == CGSize(width: 40, height: 20))
        #expect(result.screenRect == CGRect(x: 1610, y: 25, width: 40, height: 20))     // y = 50 - (5 + 20)
    }

    @Test func emptySelectionGivesNoResult() throws {
        #expect(CaptureResult.make(selection: .zero, snapshot: try makeSnapshot()) == nil)
    }

    @Test func pixelSizeMultipliesPointSizeByScale() {
        let size = ScreenCapturer.pixelSize(pointSize: CGSize(width: 1512, height: 982), scale: 2)
        #expect(size.width == 3024)
        #expect(size.height == 1964)
    }
}
