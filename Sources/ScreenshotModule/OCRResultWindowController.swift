import AppKit
import Core
import SwiftUI
import Translation

/// "识别结果"窗口。普通窗口（会激活 MyKit，因为要打字）；每次识别复用同一个窗口。
@MainActor
final class OCRResultWindowController {
    private let model: OCRResultModel
    private var window: NSWindow?

    init(settings: ScreenshotSettings) {
        model = OCRResultModel.live(settings: settings)
    }

    func recognize(_ image: CGImage) {
        show()
        Task { await model.run(on: image) }
    }

    private func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "识别结果"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 320, height: 200)
            window.contentView = NSHostingView(rootView: OCRResultView(model: model, closeTitle: "关闭", onClose: { [weak window] in
                window?.close()
            }))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// 识别结果的内容：可编辑的原文 +（可选）中文译文 + 状态 + 按钮。
/// 普通窗口（贴图右键发起）和截图遮罩上的面板共用。
struct OCRResultView: View {
    @ObservedObject var model: OCRResultModel
    let closeTitle: String
    let onClose: () -> Void
    /// 只有截图遮罩上的面板会传。true = 语言包还没装，系统马上要弹下载提示（遮罩需要临时让出层级，
    /// 否则提示会被全屏遮罩挡住）；false = 这次翻译结束了（无论成败），可以恢复。
    var onLanguageDownloadActive: ((Bool) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $model.text)
                .font(.system(size: 14))
                .padding(8)
                .overlay {
                    if model.isRecognizing {
                        ProgressView()
                    }
                }
            if model.translateEnabled {
                Divider()
                TextEditor(text: $model.translation)
                    .font(.system(size: 14))
                    .padding(8)
                    .overlay {
                        if model.isTranslating {
                            ProgressView()
                        } else if model.translation.isEmpty {
                            Text(model.translationStatus.isEmpty ? "译文会显示在这里" : model.translationStatus)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
            Divider()
            VStack(spacing: 8) {
                HStack {
                    if #available(macOS 15.0, *) {
                        Toggle("翻译成中文", isOn: Binding(
                            get: { model.translateEnabled },
                            set: { model.setTranslateEnabled($0) }
                        ))
                        .toggleStyle(.checkbox)
                        .disabled(model.isRecognizing)
                    }
                    Spacer()
                    Text(model.status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    if model.translateEnabled {
                        Button("复制译文") { model.copyTranslation() }
                            .disabled(model.translation.isEmpty)
                    }
                    Button(model.translateEnabled ? "复制原文" : "重新复制") { model.copyCurrentText() }
                        .disabled(model.text.isEmpty)
                    Button(closeTitle, action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(12)
        }
        .frame(minWidth: 320, minHeight: 200)
        .modifier(TranslationRunnerIfAvailable(model: model, onLanguageDownloadActive: onLanguageDownloadActive))
    }
}

/// 系统翻译框架需要 macOS 15；更早的系统上不显示勾选框，这个修饰器也什么都不做。
private struct TranslationRunnerIfAvailable: ViewModifier {
    let model: OCRResultModel
    let onLanguageDownloadActive: ((Bool) -> Void)?

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.modifier(TranslationRunner(model: model, onLanguageDownloadActive: onLanguageDownloadActive))
        } else {
            content
        }
    }
}

/// 用 macOS 自带的翻译（离线、免费）把英文译成简体中文。第一次使用时系统会提示下载语言包。
@available(macOS 15.0, *)
private struct TranslationRunner: ViewModifier {
    @ObservedObject var model: OCRResultModel
    let onLanguageDownloadActive: ((Bool) -> Void)?
    @ViewState private var configuration: TranslationSession.Configuration?   // 不能写 @State，见 Global Constraints

    private static let english = Locale.Language(identifier: "en")
    private static let chinese = Locale.Language(identifier: "zh-Hans")

    func body(content: Content) -> some View {
        content
            .onChange(of: model.translationRequestID) { _, _ in start() }
            .onAppear { start() }
            .translationTask(configuration) { session in
                await model.runTranslation { paragraphs in
                    try await session.prepareTranslation()      // 语言包没装时，系统在这里提示下载
                    let requests = paragraphs.enumerated().map { index, paragraph in
                        TranslationSession.Request(sourceText: paragraph, clientIdentifier: String(index))
                    }
                    var output = paragraphs
                    for response in try await session.translations(from: requests) {
                        if let index = response.clientIdentifier.flatMap({ Int($0) }), output.indices.contains(index) {
                            output[index] = response.targetText
                        }
                    }
                    return output
                }
                // 翻译结束（无论成败）。失败时如果语言包仍未装好，把提示换成具体的下载办法。
                if model.translation.isEmpty, !model.translationStatus.isEmpty,
                   await LanguageAvailability().status(from: Self.english, to: Self.chinese) != .installed {
                    model.reportLanguagePackMissing()
                }
                onLanguageDownloadActive?(false)
            }
    }

    private func start() {
        guard model.isTranslating else { return }
        Task { @MainActor in
            if let onLanguageDownloadActive {
                // 截图画面不关闭。语言包没装好时系统会弹下载提示 —— 先让全屏遮罩临时让出层级，免得挡住它
                let status = await LanguageAvailability().status(from: Self.english, to: Self.chinese)
                if status != .installed {
                    onLanguageDownloadActive(true)
                }
            }
            if configuration == nil {
                configuration = TranslationSession.Configuration(source: Self.english, target: Self.chinese)
            } else {
                configuration?.invalidate()       // 同一个窗口里再次翻译
            }
        }
    }
}
