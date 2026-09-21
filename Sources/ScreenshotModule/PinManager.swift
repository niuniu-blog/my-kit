import AppKit

/// 管理所有贴图窗口。
@MainActor
final class PinManager {
    /// 右键菜单里的 复制 / 保存 / 识别文字：参数是 (操作, 图片, 图片的 pt 尺寸)
    var onImageAction: ((CaptureAction, CGImage, CGSize) -> Void)?

    private var pins: [PinWindow] = []

    var count: Int { pins.count }

    func pin(image: CGImage, at screenRect: CGRect) {
        let window = PinWindow(image: image, screenRect: screenRect)
        window.onMenuAction = { [weak self] window, action in
            self?.handle(action, from: window)
        }
        pins.append(window)
        window.orderFrontRegardless()
    }

    func closeAll() {
        for pin in pins {
            pin.close()
        }
        pins.removeAll()      // 释放图像
    }

    private func handle(_ action: PinMenuAction, from window: PinWindow) {
        switch action {
        case .copy: onImageAction?(.copy, window.image, window.baseSize)
        case .save: onImageAction?(.save, window.image, window.baseSize)
        case .recognize: onImageAction?(.recognize, window.image, window.baseSize)
        case .close:
            window.close()
            pins.removeAll { $0 === window }
        case .closeAll:
            closeAll()
        }
    }
}
