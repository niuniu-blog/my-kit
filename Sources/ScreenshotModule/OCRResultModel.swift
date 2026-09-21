import Core
import CoreGraphics
import Foundation

/// "识别结果"窗口背后的状态。识别和复制都通过闭包注入，方便测试。
@MainActor
final class OCRResultModel: ObservableObject {
    @Published var text = ""
    @Published private(set) var status = ""
    @Published private(set) var isRecognizing = false

    // 翻译（英文 → 简体中文）。真正的翻译由界面层用系统 Translation 框架完成，这里只管状态。
    @Published private(set) var translateEnabled: Bool
    @Published var translation = ""
    @Published private(set) var translationStatus = ""
    @Published private(set) var isTranslating = false
    /// 每请求一次翻译加一；界面层观察它来启动翻译，也用它丢弃过时的结果
    @Published private(set) var translationRequestID = 0

    private let recognize: (CGImage) async throws -> String
    private let copy: (String) -> Void
    private let loadAutoTranslate: () -> Bool
    private let saveAutoTranslate: (Bool) -> Void
    /// 每次识别加一；旧的识别结果回来时如果代数变了就丢弃
    private var generation = 0

    init(
        recognize: @escaping (CGImage) async throws -> String,
        copy: @escaping (String) -> Void,
        loadAutoTranslate: @escaping () -> Bool = { false },
        saveAutoTranslate: @escaping (Bool) -> Void = { _ in }
    ) {
        self.recognize = recognize
        self.copy = copy
        self.loadAutoTranslate = loadAutoTranslate
        self.saveAutoTranslate = saveAutoTranslate
        self.translateEnabled = loadAutoTranslate()
    }

    func run(on image: CGImage) async {
        generation += 1
        let expected = generation
        text = ""
        status = "正在识别…"
        isRecognizing = true
        translation = ""
        translationStatus = ""
        isTranslating = false
        translateEnabled = loadAutoTranslate()
        let outcome: Result<String, Error>
        do {
            outcome = .success(try await recognize(image))
        } catch {
            outcome = .failure(error)
        }
        guard expected == generation else { return }
        isRecognizing = false
        switch outcome {
        case .success(let recognized) where recognized.isEmpty:
            status = "没有识别到文字"
        case .success(let recognized):
            text = recognized
            copy(recognized)
            status = "✓ 已复制全文"
            if translateEnabled { requestTranslation() }     // 选项开着：识别完自动翻译
        case .failure(let error):
            status = "识别失败：\(error.localizedDescription)"
        }
    }

    /// "重新复制"：复制文本区当前的全部内容（含用户的修改）。
    func copyCurrentText() {
        guard !text.isEmpty else { return }
        copy(text)
        status = "✓ 已复制全文"
    }

    // MARK: 翻译

    /// 勾选 / 取消"翻译成中文"。选择会被记住，下次识别沿用。
    func setTranslateEnabled(_ enabled: Bool) {
        translateEnabled = enabled
        saveAutoTranslate(enabled)
        if enabled {
            requestTranslation()
        } else {
            translation = ""
            translationStatus = ""
            isTranslating = false
        }
    }

    /// 用当前文本区的内容（含用户的修改）请求一次翻译。
    func requestTranslation() {
        translation = ""
        guard !text.isEmpty else {
            translationStatus = ""
            return
        }
        guard TranslationText.containsEnglish(text) else {
            translationStatus = "没有可翻译的英文"
            isTranslating = false
            return
        }
        isTranslating = true
        translationStatus = "正在翻译…"
        translationRequestID += 1
    }

    /// 界面层拿到翻译会话后调用。translate：输入合并好的段落，返回等长的译文数组。
    func runTranslation(_ translate: ([String]) async throws -> [String]) async {
        guard isTranslating else { return }
        let expected = translationRequestID
        let paragraphs = TranslationText.paragraphs(from: text)
        let outcome: Result<[String], Error>
        do {
            outcome = .success(try await translate(paragraphs))
        } catch {
            outcome = .failure(error)
        }
        guard expected == translationRequestID, translateEnabled else { return }
        isTranslating = false
        switch outcome {
        case .success(let translated):
            translation = translated.joined(separator: "\n")
            translationStatus = ""
        case .failure(let error):
            translationStatus = "翻译失败：\(error.localizedDescription)"
        }
    }

    /// 翻译失败且确认是因为英译中语言包没装好时调用：把提示换成具体的下载办法。
    func reportLanguagePackMissing() {
        isTranslating = false
        translation = ""
        translationStatus = "还没有安装英译中语言包。\n请在系统弹出的提示里点「下载」；\n如果没有看到提示：打开 系统设置 → 通用 → 语言与地区 → 翻译语言，\n下载「英语」和「简体中文」，然后重新勾选「翻译成中文」。"
    }

    func copyTranslation() {
        guard !translation.isEmpty else { return }
        copy(translation)
        status = "✓ 已复制译文"
    }

    /// 正式运行时用的模型：Vision 识别、写系统剪切板、"翻译成中文"的勾选状态存进设置。
    static func live(settings: ScreenshotSettings) -> OCRResultModel {
        OCRResultModel(
            recognize: { try await TextRecognizer.recognize($0) },
            copy: { PasteService.writeFromMyKit($0) },
            loadAutoTranslate: { settings.autoTranslate },
            saveAutoTranslate: { settings.autoTranslate = $0 }
        )
    }
}
