import AppKit
import Testing
@testable import ScreenshotModule

@Suite struct TextRecognizerTests {
    /// 在白底上用黑字画几行文字，生成一张 2× 的测试图片。不需要屏幕录制授权。
    private func makeImage(lines: [String]) throws -> CGImage {
        let width = 1400, height = 120 * max(lines.count, 1) + 80
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 56),
            .foregroundColor: NSColor.black,
        ]
        for (index, line) in lines.enumerated() {
            // AppKit 坐标 y 向上：第一行画在最上面
            let y = CGFloat(height) - 100 - CGFloat(index) * 120
            (line as NSString).draw(at: NSPoint(x: 40, y: y), withAttributes: attributes)
        }
        return try #require(rep.cgImage)
    }

    @Test func recognisesChineseAndEnglishInReadingOrder() async throws {
        let image = try makeImage(lines: ["MyKit 截图文字识别测试", "Hello OCR 2026"])

        let text = try await TextRecognizer.recognize(image)

        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines.first?.contains("文字识别") == true)
        #expect(lines.last?.contains("Hello") == true)
        #expect(lines.last?.contains("2026") == true)
    }

    @Test func blankImageGivesEmptyString() async throws {
        let text = try await TextRecognizer.recognize(try makeImage(lines: []))
        #expect(text == "")
    }

    // MARK: 排序（纯逻辑）

    private func fragment(_ text: String, x: CGFloat, y: CGFloat) -> TextRecognizer.Fragment {
        TextRecognizer.Fragment(text: text, box: CGRect(x: x, y: y, width: 0.2, height: 0.05))
    }

    @Test func ordersRowsTopToBottom() {
        // Vision 坐标 y 向上：y 越大越靠上
        let text = TextRecognizer.orderedText(from: [
            fragment("第三行", x: 0.1, y: 0.2),
            fragment("第一行", x: 0.1, y: 0.8),
            fragment("第二行", x: 0.1, y: 0.5),
        ])
        #expect(text == "第一行\n第二行\n第三行")
    }

    @Test func fragmentsOnTheSameRowGoLeftToRightJoinedBySpace() {
        let text = TextRecognizer.orderedText(from: [
            fragment("右", x: 0.6, y: 0.805),
            fragment("左", x: 0.1, y: 0.80),
            fragment("下一行", x: 0.1, y: 0.6),
        ])
        #expect(text == "左 右\n下一行")
    }

    @Test func noFragmentsGiveEmptyString() {
        #expect(TextRecognizer.orderedText(from: []) == "")
    }
}
