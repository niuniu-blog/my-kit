import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct TranslationTextTests {
    @Test func detectsEnglish() {
        #expect(TranslationText.containsEnglish("Click Save to continue"))
        #expect(TranslationText.containsEnglish("版本 Version 2"))
        #expect(!TranslationText.containsEnglish("北京亚太宏图 2026"))
        #expect(!TranslationText.containsEnglish("A 级"))            // 单个字母不算英文
        #expect(!TranslationText.containsEnglish(""))
    }

    @Test func mergesWrappedLinesOfOneParagraph() {
        let ocr = """
        The quick brown fox jumps over the lazy dog and keeps
        running through the forest until it reaches the river
        bank.
        """
        #expect(TranslationText.paragraphs(from: ocr) == [
            "The quick brown fox jumps over the lazy dog and keeps running through the forest until it reaches the river bank."
        ])
    }

    @Test func sentenceEndingPunctuationStartsANewParagraph() {
        let ocr = """
        This is the first sentence of the document here.
        This is the second one and it is about as long too.
        """
        #expect(TranslationText.paragraphs(from: ocr).count == 2)
    }

    @Test func shortLinesLikeMenusAndHeadingsAreNotMerged() {
        let ocr = """
        Settings
        General
        The quick brown fox jumps over the lazy dog and keeps
        running.
        """
        #expect(TranslationText.paragraphs(from: ocr) == [
            "Settings",
            "General",
            "The quick brown fox jumps over the lazy dog and keeps running.",
        ])
    }

    @Test func listOfShortLinesIsNeverMergedEvenWhenAllAreEquallyShort() {
        #expect(TranslationText.paragraphs(from: "Settings\nGeneral\nAbout us") == ["Settings", "General", "About us"])
    }

    @Test func blankLinesSeparateParagraphsAndAreDropped() {
        #expect(TranslationText.paragraphs(from: "Hello there\n\n  \nGood bye") == ["Hello there", "Good bye"])
        #expect(TranslationText.paragraphs(from: " \n ").isEmpty)
    }
}

@MainActor
@Suite struct OCRResultModelTranslationTests {
    private final class Prefs {
        var autoTranslate = false
    }

    private struct Boom: LocalizedError {
        var errorDescription: String? { "语言包不可用" }
    }

    private func makeImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try #require(context.makeImage())
    }

    private func makeModel(recognized: String, prefs: Prefs) -> OCRResultModel {
        OCRResultModel(
            recognize: { _ in recognized },
            copy: { _ in },
            loadAutoTranslate: { prefs.autoTranslate },
            saveAutoTranslate: { prefs.autoTranslate = $0 }
        )
    }

    @Test func translationIsOffByDefaultAndNothingIsRequested() async throws {
        let model = makeModel(recognized: "Hello world", prefs: Prefs())
        await model.run(on: try makeImage())
        #expect(!model.translateEnabled)
        #expect(model.translationRequestID == 0)
        #expect(model.translation.isEmpty)
    }

    @Test func enablingRequestsTranslationAndRemembersTheChoice() async throws {
        let prefs = Prefs()
        let model = makeModel(recognized: "Hello world", prefs: prefs)
        await model.run(on: try makeImage())

        model.setTranslateEnabled(true)

        #expect(prefs.autoTranslate)
        #expect(model.translateEnabled)
        #expect(model.isTranslating)
        #expect(model.translationRequestID == 1)
        #expect(model.translationStatus == "正在翻译…")
    }

    @Test func rememberedChoiceTranslatesAutomaticallyAfterRecognition() async throws {
        let prefs = Prefs()
        prefs.autoTranslate = true
        let model = makeModel(recognized: "Hello world", prefs: prefs)

        await model.run(on: try makeImage())

        #expect(model.translateEnabled)
        #expect(model.translationRequestID == 1)
    }

    @Test func runTranslationSendsMergedParagraphsAndJoinsResults() async throws {
        let prefs = Prefs()
        let model = makeModel(recognized: "Settings\nThe quick brown fox jumps over the lazy dog and keeps\nrunning.", prefs: prefs)
        await model.run(on: try makeImage())
        model.setTranslateEnabled(true)

        var received: [String] = []
        await model.runTranslation { paragraphs in
            received = paragraphs
            return ["设置", "敏捷的棕色狐狸跳过懒狗，继续奔跑。"]
        }

        #expect(received == ["Settings", "The quick brown fox jumps over the lazy dog and keeps running."])
        #expect(model.translation == "设置\n敏捷的棕色狐狸跳过懒狗，继续奔跑。")
        #expect(!model.isTranslating)
        #expect(model.translationStatus == "")
    }

    @Test func textWithoutEnglishIsNotSentForTranslation() async throws {
        let model = makeModel(recognized: "北京亚太宏图科技有限公司", prefs: Prefs())
        await model.run(on: try makeImage())

        model.setTranslateEnabled(true)

        #expect(model.translationRequestID == 0)
        #expect(!model.isTranslating)
        #expect(model.translationStatus == "没有可翻译的英文")
    }

    @Test func failureIsReported() async throws {
        let model = makeModel(recognized: "Hello world", prefs: Prefs())
        await model.run(on: try makeImage())
        model.setTranslateEnabled(true)

        await model.runTranslation { _ in throw Boom() }

        #expect(model.translation.isEmpty)
        #expect(!model.isTranslating)
        #expect(model.translationStatus == "翻译失败：语言包不可用")
    }

    @Test func disablingClearsTranslationAndForgetsTheChoice() async throws {
        let prefs = Prefs()
        let model = makeModel(recognized: "Hello world", prefs: prefs)
        await model.run(on: try makeImage())
        model.setTranslateEnabled(true)
        await model.runTranslation { _ in ["你好，世界"] }

        model.setTranslateEnabled(false)

        #expect(!prefs.autoTranslate)
        #expect(model.translation.isEmpty)
        #expect(model.translationStatus == "")
    }

    @Test func newRecognitionClearsOldTranslation() async throws {
        let prefs = Prefs()
        let model = makeModel(recognized: "Hello world", prefs: prefs)
        await model.run(on: try makeImage())
        model.setTranslateEnabled(true)
        await model.runTranslation { _ in ["你好，世界"] }

        await model.run(on: try makeImage())

        #expect(model.translation.isEmpty)           // 旧译文清掉
        #expect(model.translationRequestID == 2)     // 并且因为选项开着，自动再次请求翻译
    }

    @Test func copyTranslationCopiesTheChineseText() async throws {
        var copied: [String] = []
        let model = OCRResultModel(
            recognize: { _ in "Hello world" },
            copy: { copied.append($0) },
            loadAutoTranslate: { false },
            saveAutoTranslate: { _ in }
        )
        await model.run(on: try makeImage())
        model.setTranslateEnabled(true)
        await model.runTranslation { _ in ["你好，世界"] }

        model.copyTranslation()

        #expect(copied == ["Hello world", "你好，世界"])
        #expect(model.status == "✓ 已复制译文")
    }
}

@Suite struct ScreenshotAutoTranslateSettingTests {
    @Test func autoTranslateDefaultsToOffAndRoundTrips() {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        #expect(!ScreenshotSettings(defaults: defaults).autoTranslate)
        ScreenshotSettings(defaults: defaults).autoTranslate = true
        #expect(ScreenshotSettings(defaults: defaults).autoTranslate)
    }
}
