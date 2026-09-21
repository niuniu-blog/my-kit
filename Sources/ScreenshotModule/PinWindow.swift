import AppKit

/// 贴图窗口的右键菜单要做的事，由 PinManager 转给 ScreenshotActions。
enum PinMenuAction {
    case copy, save, recognize, close, closeAll
}

/// 一张贴图：无边框、浮在所有窗口上面、不抢焦点。
final class PinWindow: NSPanel {
    let image: CGImage
    let baseSize: CGSize
    var onMenuAction: ((PinWindow, PinMenuAction) -> Void)?
    private(set) var zoom: CGFloat = 1

    /// screenRect：AppKit 全局坐标，贴图出现的位置（= 截图时选区的位置）
    init(image: CGImage, screenRect: CGRect) {
        self.image = image
        self.baseSize = screenRect.size
        super.init(
            contentRect: screenRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false        // 拖动由 PinContentView 自己处理，这样才能同时识别双击
        contentView = PinContentView(image: image, owner: self)
        setFrame(screenRect, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func applyScroll(deltaY: CGFloat) {
        applyZoom(PinZoom.scale(current: zoom, scrollDeltaY: deltaY))
    }

    /// 触控板双指捏合
    func applyMagnification(_ magnification: CGFloat) {
        applyZoom(PinZoom.scale(current: zoom, magnification: magnification))
    }

    private func applyZoom(_ next: CGFloat) {
        guard next != zoom else { return }
        zoom = next
        setFrame(PinZoom.frame(current: frame, baseSize: baseSize, scale: zoom), display: true)
    }

    fileprivate func send(_ action: PinMenuAction) {
        onMenuAction?(self, action)
    }
}

private final class PinContentView: NSView {
    private weak var owner: PinWindow?

    init(image: CGImage, owner: PinWindow) {
        self.owner = owner
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            owner?.send(.close)                    // 双击关闭
        } else {
            window?.performDrag(with: event)       // 拖动移动
        }
    }

    override func scrollWheel(with event: NSEvent) {
        owner?.applyScroll(deltaY: event.scrollingDeltaY)
    }

    /// 触控板双指捏合：张开放大、捏拢缩小
    override func magnify(with event: NSEvent) {
        owner?.applyMagnification(event.magnification)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let entries: [(String, Selector)] = [
            ("复制", #selector(copyImage)),
            ("保存", #selector(saveImage)),
            ("识别文字", #selector(recognizeText)),
        ]
        for (title, action) in entries {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let close = NSMenuItem(title: "关闭", action: #selector(closePin), keyEquivalent: "")
        close.target = self
        menu.addItem(close)
        let closeAll = NSMenuItem(title: "关闭全部贴图", action: #selector(closeAllPins), keyEquivalent: "")
        closeAll.target = self
        menu.addItem(closeAll)
        return menu
    }

    @objc private func copyImage() { owner?.send(.copy) }
    @objc private func saveImage() { owner?.send(.save) }
    @objc private func recognizeText() { owner?.send(.recognize) }
    @objc private func closePin() { owner?.send(.close) }
    @objc private func closeAllPins() { owner?.send(.closeAll) }
}
