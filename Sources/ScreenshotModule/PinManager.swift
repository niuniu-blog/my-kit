import AppKit
import os

/// 管理所有贴图窗口。
@MainActor
final class PinManager {
    /// 右键菜单里的 复制 / 保存 / 识别文字：参数是 (操作, 图片, 图片的 pt 尺寸)
    var onImageAction: ((CaptureAction, CGImage, CGSize) -> Void)?

    private var pins: [PinWindow] = []
    /// 只在有贴图时存在。贴图不抢焦点、MyKit 也不是前台软件，系统会把触控板的捏合手势发给前台软件，
    /// 贴图自己收不到；所以额外监听"发给别的软件的捏合手势"，指针停在贴图上时就缩放那张贴图。
    private var magnifyMonitor: Any?
    private let log = Logger(subsystem: "com.imiros.mykit", category: "pin")

    var count: Int { pins.count }

    func pin(image: CGImage, at screenRect: CGRect) {
        let window = PinWindow(image: image, screenRect: screenRect)
        window.onMenuAction = { [weak self] window, action in
            self?.handle(action, from: window)
        }
        pins.append(window)
        window.orderFrontRegardless()
        updateMagnifyMonitor()
    }

    func closeAll() {
        for pin in pins {
            pin.close()
        }
        pins.removeAll()      // 释放图像
        updateMagnifyMonitor()
    }

    // MARK: 捏合缩放

    private func updateMagnifyMonitor() {
        if pins.isEmpty {
            if let magnifyMonitor {
                NSEvent.removeMonitor(magnifyMonitor)
                self.magnifyMonitor = nil
            }
        } else if magnifyMonitor == nil {
            magnifyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .magnify) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.handleMagnifySentElsewhere(event)
                }
            }
        }
    }

    private func handleMagnifySentElsewhere(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        let top = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        let candidates = pins.map { PinHitTest.Candidate(windowNumber: $0.windowNumber, frame: $0.frame) }
        guard let index = PinHitTest.index(at: point, topWindowNumber: top > 0 ? top : nil, candidates: candidates) else { return }
        if event.phase == .began {
            log.info("捏合手势：经由全局监听送达贴图")
        }
        pins[index].applyMagnification(event.magnification)
    }

    private func handle(_ action: PinMenuAction, from window: PinWindow) {
        switch action {
        case .copy: onImageAction?(.copy, window.image, window.baseSize)
        case .save: onImageAction?(.save, window.image, window.baseSize)
        case .recognize: onImageAction?(.recognize, window.image, window.baseSize)
        case .close:
            window.close()
            pins.removeAll { $0 === window }
            updateMagnifyMonitor()
        case .closeAll:
            closeAll()
        }
    }
}
