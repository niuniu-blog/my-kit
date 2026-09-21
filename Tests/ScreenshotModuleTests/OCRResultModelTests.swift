import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@MainActor
@Suite struct OCRResultModelTests {
    private final class CopyLog {
        var values: [String] = []
    }

    private struct Boom: LocalizedError {
        var errorDescription: String? { "图片无法处理" }
    }

    private func makeImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try #require(context.makeImage())
    }

    @Test func successFillsTextCopiesItAndReportsCopied() async throws {
        let log = CopyLog()
        let model = OCRResultModel(recognize: { _ in "第一行\n第二行" }, copy: { log.values.append($0) })

        await model.run(on: try makeImage())

        #expect(model.text == "第一行\n第二行")
        #expect(model.status == "✓ 已复制全文")
        #expect(!model.isRecognizing)
        #expect(log.values == ["第一行\n第二行"])
    }

    @Test func emptyResultDoesNotTouchClipboard() async throws {
        let log = CopyLog()
        let model = OCRResultModel(recognize: { _ in "" }, copy: { log.values.append($0) })

        await model.run(on: try makeImage())

        #expect(model.text == "")
        #expect(model.status == "没有识别到文字")
        #expect(log.values.isEmpty)
    }

    @Test func failureShowsReasonAndDoesNotCopy() async throws {
        let log = CopyLog()
        let model = OCRResultModel(recognize: { _ in throw Boom() }, copy: { log.values.append($0) })

        await model.run(on: try makeImage())

        #expect(model.status == "识别失败：图片无法处理")
        #expect(!model.isRecognizing)
        #expect(log.values.isEmpty)
    }

    @Test func copyAgainUsesEditedText() async throws {
        let log = CopyLog()
        let model = OCRResultModel(recognize: { _ in "识别有错字" }, copy: { log.values.append($0) })
        await model.run(on: try makeImage())

        model.text = "识别没有错字"
        model.copyCurrentText()

        #expect(log.values == ["识别有错字", "识别没有错字"])
    }

    @Test func copyAgainWithEmptyTextDoesNothing() {
        let log = CopyLog()
        let model = OCRResultModel(recognize: { _ in "" }, copy: { log.values.append($0) })
        model.copyCurrentText()
        #expect(log.values.isEmpty)
    }

    @Test func newRunClearsPreviousText() async throws {
        var results = ["第一次", ""]
        let model = OCRResultModel(recognize: { _ in results.removeFirst() }, copy: { _ in })

        await model.run(on: try makeImage())
        await model.run(on: try makeImage())

        #expect(model.text == "")
        #expect(model.status == "没有识别到文字")
    }
}
