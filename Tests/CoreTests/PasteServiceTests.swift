import AppKit
import Testing
@testable import Core

@Suite struct PasteServiceTests {
    @Test func writePutsTextAndOwnMarkerOnPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("mykit-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        PasteService.write("你好 MyKit", to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "你好 MyKit")
        #expect(pasteboard.types?.contains(PasteService.ownWriteType) == true)
    }

    @Test func writeReplacesPreviousContent() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("mykit-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        PasteService.write("first", to: pasteboard)
        let countAfterFirst = pasteboard.changeCount
        PasteService.write("second", to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "second")
        #expect(pasteboard.changeCount > countAfterFirst)
    }

    @Test func writeFromMyKitCarriesOriginMarkerButNotOwnWriteMarker() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("mykit-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        PasteService.writeFromMyKit("识别出来的文字", to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "识别出来的文字")
        #expect(pasteboard.types?.contains(PasteService.originMarkerType) == true)
        #expect(pasteboard.types?.contains(PasteService.ownWriteType) == false)
        #expect(PasteService.originMarkerType.rawValue == "com.imiros.mykit.origin")
    }

    @Test func writeImagePutsPNGAndTIFFOnPasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("mykit-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let context = try #require(CGContext(
            data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let image = try #require(context.makeImage())

        let ok = PasteService.write(image: image, pointSize: CGSize(width: 20, height: 10), to: pasteboard)

        #expect(ok)
        let png = try #require(pasteboard.data(forType: .png))
        let decoded = try #require(NSBitmapImageRep(data: png))
        #expect(decoded.pixelsWide == 40)
        #expect(decoded.pixelsHigh == 20)
        #expect(pasteboard.data(forType: .tiff) != nil)
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test func ownWriteTypeMatchesTheSpecIdentifier() {
        #expect(PasteService.ownWriteType.rawValue == "com.imiros.mykit.own-write")
    }
}
