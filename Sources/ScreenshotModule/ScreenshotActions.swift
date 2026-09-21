import AppKit
import Core

/// 复制 / 保存 / 识别文字 / 贴图 的执行，以及它们的提示文案。
@MainActor
final class ScreenshotActions {
    let pins = PinManager()
    private let settings: ScreenshotSettings
    private let saver: ScreenshotSaver
    private let ocrWindow: OCRResultWindowController

    init(settings: ScreenshotSettings, saver: ScreenshotSaver = ScreenshotSaver()) {
        self.settings = settings
        self.saver = saver
        self.ocrWindow = OCRResultWindowController(settings: settings)
        pins.onImageAction = { [weak self] action, image, pointSize in
            self?.perform(action, image: image, pointSize: pointSize, screenRect: nil)
        }
    }

    /// screenRect 只有贴图用得到；从贴图的右键菜单发起的操作传 nil。
    func perform(_ action: CaptureAction, image: CGImage, pointSize: CGSize, screenRect: CGRect?) {
        switch action {
        case .copy:
            let ok = PasteService.write(image: image, pointSize: pointSize)
            Toast.show(ok ? "已复制" : "复制失败")
        case .save:
            let outcome = saver.save(image, pointSize: pointSize, to: settings.saveFolder)
            Toast.show(Self.message(for: outcome))
        case .recognize:
            ocrWindow.recognize(image)
        case .pin:
            guard let screenRect else { return }
            pins.pin(image: image, at: screenRect)
        }
    }

    /// 保存结果 → 提示文案。文件夹用系统显示的名字（"桌面"而不是 "Desktop"）。
    static func message(for outcome: SaveOutcome) -> String {
        switch outcome {
        case .saved(let url):
            return "已保存到 \(FileManager.default.displayName(atPath: url.deletingLastPathComponent().path))"
        case .savedToFallback:
            return "保存失败，已改存到桌面"
        case .failed:
            return "保存失败"
        }
    }
}
