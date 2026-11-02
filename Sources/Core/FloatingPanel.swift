import AppKit
import SwiftUI

/// 不抢焦点的浮动面板：能接收键盘输入，但不会让 MyKit 变成前台 App，
/// 所以原来的 App 保持前台和光标位置，关闭面板后可以直接向它粘贴。
public final class FloatingPanel: NSPanel {
    public var onClose: (() -> Void)?
    /// 返回 true 表示按键已处理，不再继续传给输入框。
    public var keyHandler: ((NSEvent) -> Bool)?

    private let panelSize: NSSize
    private var isClosing = false

    public init(size: NSSize) {
        self.panelSize = size
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    /// 输入法正在组字（比如拼音还没选词）时，回车 / 方向键应该交给输入法。
    public var isComposingText: Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    /// 面板位置：水平居中，顶边在屏幕可见区域自上而下 20% 处，且不超出可见区域。
    public static func frame(for size: NSSize, inVisibleFrame visible: NSRect) -> NSRect {
        let x = visible.midX - size.width / 2
        var y = visible.maxY - visible.height * 0.2 - size.height
        y = max(y, visible.minY)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// frame 为 nil 时放在鼠标所在屏幕的中央偏上；否则用给定的位置（AppKit 全局坐标）。
    public func present<Content: View>(_ view: Content, at frame: NSRect? = nil) {
        contentView = NSHostingView(rootView: view)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let frame {
            setFrame(frame, display: true)
        } else if let screen {
            setFrame(Self.frame(for: panelSize, inVisibleFrame: screen.visibleFrame), display: true)
        }
        orderFrontRegardless()
        makeKey()
    }

    /// 失去键盘焦点时是否自动关闭（点击面板外部即关闭）。需要在系统提示框抢走焦点时
    /// 保持显示的面板（如截图遮罩上的识别结果）设为 false，由使用方自己决定何时关闭。
    public var closesOnResignKey = true

    public override func resignKey() {
        super.resignKey()
        if closesOnResignKey { close() }
    }

    public override func close() {
        guard !isClosing else { return }   // close 过程中会触发 resignKey，避免重入
        isClosing = true
        defer { isClosing = false }
        let wasVisible = isVisible
        super.close()
        if wasVisible { onClose?() }
    }

    public override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true { return true }
        if EditShortcuts.perform(event, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}
