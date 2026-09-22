import AppKit
import Core

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

    /// 文字标注的输入框正在编辑时，它是第一响应者
    private var editingTextView: NSTextView? {
        firstResponder as? NSTextView
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if let editor = editingTextView {
                // 正在输入文字：按键交给输入框（含中文输入法）。只有 Esc 例外 —— 而且输入法正在组字时 Esc 也归输入法
                if event.keyCode == 53, !editor.hasMarkedText() {
                    _ = keyHandler?(event)
                    return
                }
                super.sendEvent(event)
                return
            }
            _ = keyHandler?(event)
            return                       // 截图期间其余按键到此为止（也避免系统"咚"一声）
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let editor = editingTextView {
            forwardEditingShortcut(event, to: editor)
            return true
        }
        _ = keyHandler?(event)
        return true                      // ⌘ 组合键同样不再往下传
    }

    /// MyKit 没有主菜单，输入框里的 ⌘X / ⌘C / ⌘V / ⌘A / ⌘Z / ⇧⌘Z 要自己转发。
    private func forwardEditingShortcut(_ event: NSEvent, to editor: NSTextView) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return }
        if modifiers == [.command, .shift], key == "z" {
            editor.undoManager?.redo()
            return
        }
        guard modifiers == .command else { return }
        switch key {
        case "x": editor.cut(nil)
        case "c": editor.copy(nil)
        case "v": editor.pasteAsPlainText(nil)
        case "a": editor.selectAll(nil)
        case "z": editor.undoManager?.undo()
        default: break
        }
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

    /// 识别文字时遮罩不关闭：结果面板浮在遮罩上面、选区旁边，方便对照原图。
    private var ocrPanel: FloatingPanel?
    private let ocrModel: OCRResultModel
    private static let ocrPanelSize = NSSize(width: 400, height: 440)      // 留出下半部分显示译文
    /// 系统正在（或即将）显示"下载翻译语言包"的提示：遮罩临时降到普通窗口层级，提示才不会被挡住
    private var isYieldingToSystemPrompt = false

    /// cgWindows：截图那一刻屏幕上的窗口边框（CG 全局坐标，前 → 后）
    init(snapshots: [DisplaySnapshot], cgWindows: [CGRect], settings: ScreenshotSettings = ScreenshotSettings()) {
        ocrModel = OCRResultModel.live(settings: settings)
        entries = snapshots.map { snapshot in
            let panel = OverlayPanel(screenFrame: snapshot.screen.frame)
            let localBounds = snapshot.localBounds

            let imageView = NSImageView(frame: localBounds)
            imageView.image = NSImage(cgImage: snapshot.image, size: localBounds.size)
            imageView.imageScaling = .scaleAxesIndependently
            imageView.imageFrameStyle = .none
            imageView.autoresizingMask = [.width, .height]

            let windows = WindowLocator.localRects(cgWindows: cgWindows, displayBounds: snapshot.screen.cgBounds)
            let overlay = OverlayView(
                frame: localBounds, windows: windows,
                snapshotImage: snapshot.image, imageScale: snapshot.imageScale,
                annotationSettings: settings.annotation
            )
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
        dismissOCRPanel()
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
        dismissOCRPanel()                      // 点一下定格画面 = 收起识别结果，继续截图
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
        case .exit:
            // Esc / ✕：按一下就退出。正在打字的那块屏先完成输入，这一下就到此为止
            let finishedText = entries.contains { !$0.view.handleEscape() }
            if !finishedText { end() }

        case .stepBack:
            // 右键：每块屏按层级退一级（完成文字 → 取消工具 → 清选区和标注）；哪块屏都没东西可取消 → 退出截图
            var cancelledSomething = false
            for entry in entries where !entry.view.handleCancel() {
                cancelledSomething = true
            }
            if !cancelledSomething { end() }

        case .undo:
            entries.first(where: { $0.view.model.hasConfirmedSelection })?.view.undo()

        case .redo:
            entries.first(where: { $0.view.model.hasConfirmedSelection })?.view.redo()

        case .perform(let action):
            guard let entry = entries.first(where: { $0.view.model.hasConfirmedSelection }),
                  let selection = entry.view.model.selection
            else { return }                     // 还没有选区：按键无效果
            entry.view.commitPendingText()      // 还在输入框里的文字先落成标注
            guard let result = CaptureResult.make(
                selection: selection, snapshot: entry.snapshot, annotations: entry.view.annotations
            ) else { return }
            if action == .recognize {
                showRecognition(of: result, selection: selection, in: entry)   // 遮罩保持打开
                return
            }
            end()
            onFinish?(action, result)
        }
    }

    // MARK: 识别文字（遮罩不关闭）

    private func showRecognition(of result: CaptureResult, selection: CGRect, in entry: Entry) {
        dismissOCRPanel()
        let size = Self.ocrPanelSize
        let origin = ToolbarPlacement.sidePanelOrigin(panelSize: size, selection: selection, bounds: entry.snapshot.localBounds)
        let frame = ScreenGeometry.appKitRect(
            fromLocal: CGRect(origin: origin, size: size),
            screenFrame: entry.snapshot.screen.frame
        )

        let panel = FloatingPanel(size: size)
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)   // 盖在遮罩上面
        // 系统的下载提示会抢走键盘焦点；面板不能因此关闭（否则翻译到一半就没了）。
        // 只有点击定格画面 / 工具条时才收起，见 overlayViewDidBeginInteraction。
        panel.closesOnResignKey = false
        panel.keyHandler = { [weak self, weak panel] event in
            // Esc = 结束整个截图；输入法正在组字时 Esc 交给输入法
            guard event.keyCode == 53, panel?.isComposingText != true else { return false }
            self?.end()
            return true
        }
        // 面板失去焦点（用户点了定格画面）时会自己关闭
        panel.onClose = { [weak self, weak panel] in
            if self?.ocrPanel === panel { self?.ocrPanel = nil }
        }
        ocrPanel = panel
        panel.present(
            OCRResultView(
                model: ocrModel,
                closeTitle: "完成",
                onClose: { [weak self] in self?.end() },
                onLanguageDownloadActive: { [weak self] active in self?.yieldToSystemPrompt(active) }
            ),
            at: frame
        )
        Task { [ocrModel] in
            await ocrModel.run(on: result.ocrImage)      // 原图 + 仅马赛克：被遮住的不识别，箭头等不干扰
        }
    }

    /// 截图画面始终不关闭。需要下载语言包时只是临时让出窗口层级：画面还在，菜单栏会露出来；
    /// 翻译结束（或面板收起、截图结束）后恢复。
    private func yieldToSystemPrompt(_ yielding: Bool) {
        guard yielding != isYieldingToSystemPrompt else { return }
        isYieldingToSystemPrompt = yielding
        let shielding = Int(CGShieldingWindowLevel())
        for entry in entries {
            entry.panel.level = yielding ? .normal : NSWindow.Level(rawValue: shielding)
        }
        ocrPanel?.level = yielding ? .normal : NSWindow.Level(rawValue: shielding + 1)
        if yielding {
            ocrPanel?.orderFront(nil)      // 同为普通层级时，保证结果面板仍在定格画面上面
        }
    }

    private func dismissOCRPanel() {
        yieldToSystemPrompt(false)
        guard let panel = ocrPanel else { return }
        ocrPanel = nil
        panel.onClose = nil
        panel.close()
    }
}
