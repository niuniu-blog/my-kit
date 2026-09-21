import AppKit

/// 盖住整块屏幕的面板。和剪切板面板一样：能接收键盘，但不会让 MyKit 变成前台 App。
final class OverlayPanel: NSPanel {
    /// 返回 true 表示已处理
    var keyHandler: ((NSEvent) -> Bool)?

    init(screenFrame: CGRect) {
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))     // 盖过菜单栏和 Dock
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        setFrame(screenFrame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            _ = keyHandler?(event)
            return                       // 截图期间所有按键到此为止（也避免系统"咚"一声）
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        _ = keyHandler?(event)
        return true                      // ⌘ 组合键同样不再往下传
    }
}

/// 一次截图会话：每块屏一个遮罩面板；选好并执行某个操作、或取消后结束。
@MainActor
final class CaptureOverlayController: OverlayViewDelegate {
    /// 用户选好区域并选择了一个操作。调用时遮罩已经关闭。
    var onFinish: ((CaptureAction, CaptureResult) -> Void)?
    /// 会话结束（无论是完成还是取消）时一定会调用一次。
    var onEnd: (() -> Void)?

    private struct Entry {
        let snapshot: DisplaySnapshot
        let panel: OverlayPanel
        let view: OverlayView
    }

    private var entries: [Entry] = []
    private var hasEnded = false

    /// cgWindows：截图那一刻屏幕上的窗口边框（CG 全局坐标，前 → 后）
    init(snapshots: [DisplaySnapshot], cgWindows: [CGRect]) {
        entries = snapshots.map { snapshot in
            let panel = OverlayPanel(screenFrame: snapshot.screen.frame)
            let localBounds = snapshot.localBounds

            let imageView = NSImageView(frame: localBounds)
            imageView.image = NSImage(cgImage: snapshot.image, size: localBounds.size)
            imageView.imageScaling = .scaleAxesIndependently
            imageView.imageFrameStyle = .none
            imageView.autoresizingMask = [.width, .height]

            let windows = WindowLocator.localRects(cgWindows: cgWindows, displayBounds: snapshot.screen.cgBounds)
            let overlay = OverlayView(frame: localBounds, windows: windows)
            overlay.autoresizingMask = [.width, .height]

            let container = NSView(frame: localBounds)
            container.addSubview(imageView)
            container.addSubview(overlay)
            panel.contentView = container
            return Entry(snapshot: snapshot, panel: panel, view: overlay)
        }
        for entry in entries {
            entry.view.delegate = self
            entry.panel.keyHandler = { [weak self] event in
                self?.handleKey(event) ?? false
            }
        }
    }

    func begin() {
        let mouse = NSEvent.mouseLocation
        for entry in entries {
            entry.panel.orderFrontRegardless()
        }
        let underMouse = entries.first { NSMouseInRect(mouse, $0.snapshot.screen.frame, false) } ?? entries.first
        underMouse?.panel.makeKey()
        underMouse?.panel.makeFirstResponder(underMouse?.view)
        NSCursor.crosshair.set()
    }

    func end() {
        guard !hasEnded else { return }
        hasEnded = true
        for entry in entries {
            entry.panel.keyHandler = nil
            entry.panel.contentView = nil      // 立刻释放定格画面
            entry.panel.close()
        }
        entries.removeAll()
        NSCursor.arrow.set()
        onEnd?()
    }

    // MARK: OverlayViewDelegate

    func overlayViewDidBeginInteraction(_ view: OverlayView) {
        for entry in entries where entry.view !== view {
            entry.view.resetSelection()        // 同一时间只有一块屏上有选区
        }
    }

    func overlayView(_ view: OverlayView, didRequest command: OverlayCommand) {
        handle(command)
    }

    // MARK: 指令

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              let command = OverlayKeyMap.command(
                  keyCode: event.keyCode,
                  characters: event.charactersIgnoringModifiers,
                  modifiers: event.modifierFlags
              )
        else { return false }
        handle(command)
        return true
    }

    private func handle(_ command: OverlayCommand) {
        switch command {
        case .cancel:
            // 第一级：清掉选区；没有任何选区可清 → 退出截图
            var clearedSomething = false
            for entry in entries where !entry.view.cancelSelection() {
                clearedSomething = true
            }
            if !clearedSomething { end() }

        case .perform(let action):
            guard let entry = entries.first(where: { $0.view.model.hasConfirmedSelection }),
                  let selection = entry.view.model.selection,
                  let result = CaptureResult.make(selection: selection, snapshot: entry.snapshot)
            else { return }                     // 还没有选区：按键无效果
            end()
            onFinish?(action, result)
        }
    }
}
