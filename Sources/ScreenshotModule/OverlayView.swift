import AppKit

@MainActor
protocol OverlayViewDelegate: AnyObject {
    /// 用户开始在这块屏上操作（其他屏的选区要清掉）
    func overlayViewDidBeginInteraction(_ view: OverlayView)
    func overlayView(_ view: OverlayView, didRequest command: OverlayCommand)
}

/// 盖在定格画面上面的那一层：画暗层、高亮 / 选区、手柄、尺寸标签和标注，
/// 并把鼠标事件交给 SelectionModel（调整选区）或 AnnotationModel（画标注）。
/// isFlipped = true，所以视图坐标就是"屏内坐标"（左上角原点）。
final class OverlayView: NSView {
    weak var delegate: OverlayViewDelegate?
    private(set) var model: SelectionModel
    private(set) var annotation: AnnotationModel

    private let toolbar = CaptureToolbar()
    private let styleBar = AnnotationStyleBar()
    private let snapshotImage: CGImage
    private let imageScale: CGFloat
    private let annotationSettings: AnnotationSettings
    /// 只在这次截图会话内有效，随视图一起释放
    private let mosaicCache = MosaicCache()
    /// 选区裁剪出来的原图（马赛克从它取像素）；选区变了就重新裁
    private var baseCrop: (selection: CGRect, image: CGImage)?
    /// 文字工具的输入框（正在输入时才有）
    private var textEditor: NSTextView?
    /// 这次鼠标拖动是在画标注（而不是在调整选区）
    private var isAnnotating = false

    private static let handleSide: CGFloat = 8
    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    init(frame: NSRect, windows: [CGRect], snapshotImage: CGImage, imageScale: CGFloat, annotationSettings: AnnotationSettings) {
        model = SelectionModel(bounds: CGRect(origin: .zero, size: frame.size), windows: windows)
        annotation = AnnotationModel(color: annotationSettings.color, size: annotationSettings.size)
        self.snapshotImage = snapshotImage
        self.imageScale = imageScale
        self.annotationSettings = annotationSettings
        super.init(frame: frame)

        toolbar.isHidden = true
        toolbar.onCommand = { [weak self] command in
            guard let self else { return }
            self.delegate?.overlayView(self, didRequest: command)
        }
        toolbar.onToolToggle = { [weak self] tool in
            self?.toggleTool(tool)
        }
        styleBar.isHidden = true
        styleBar.onColor = { [weak self] color in
            self?.setColor(color)
        }
        styleBar.onSize = { [weak self] size in
            self?.setSize(size)
        }
        addSubview(toolbar)
        addSubview(styleBar)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: 给控制器用

    /// 已完成的标注（选区内坐标），导出时合成到图上。
    var annotations: [Annotation] { annotation.items }

    /// Esc / 右键。按层级处理一级；返回 true 表示这块屏上已经没有任何东西可取消（控制器据此决定是否退出截图）。
    func handleCancel() -> Bool {
        let level = OverlayCancel.level(
            isEditingText: textEditor != nil,
            hasTool: annotation.tool != nil,
            hasSelection: model.selection != nil || model.isAdjusting
        )
        switch level {
        case .finishText:
            commitPendingText()
            return false
        case .deselectTool:
            annotation.deselectTool()
            refresh()
            return false
        case .clearSelection:
            clearEverything()
            return false
        case .exitCapture:
            return true
        }
    }

    /// 另一块屏开始操作时：这块屏的选区和标注全部清掉。
    func resetSelection() {
        clearEverything()
    }

    func undo() {
        if textEditor != nil {
            discardTextEditor()              // 正在输入的文字还没变成标注：撤销 = 放弃这次输入
        } else {
            annotation.undo()
        }
        refresh()
    }

    func redo() {
        commitPendingText()
        annotation.redo()
        refresh()
    }

    /// 执行复制 / 保存等操作之前调用：把还在输入框里的文字落成标注。
    func commitPendingText() {
        guard let editor = textEditor else { return }
        let text = editor.string
        let frame = editor.frame
        discardTextEditor()
        if let selection = model.selection {
            annotation.placeText(text, at: CGPoint(x: frame.minX - selection.minX, y: frame.minY - selection.minY))
        }
        refresh()
    }

    // MARK: 标注工具与样式

    private func toggleTool(_ tool: AnnotationTool) {
        commitPendingText()
        annotation.toggleTool(tool)
        refresh()
    }

    private func setColor(_ color: AnnotationColor) {
        annotation.color = color
        annotationSettings.color = color              // 记住，下次截图沿用
        applyStyleToTextEditor()
        refresh()
    }

    private func setSize(_ size: AnnotationSize) {
        annotation.size = size
        annotationSettings.size = size
        applyStyleToTextEditor()
        refresh()
    }

    private func clearEverything() {
        discardTextEditor()
        isAnnotating = false
        model.reset()
        annotation.reset()
        mosaicCache.removeAll()
        baseCrop = nil
        refresh()
    }

    // MARK: 文字输入框

    private var textFont: NSFont {
        .systemFont(ofSize: annotation.size.fontSize, weight: .medium)
    }

    private func beginTextEditing(at point: CGPoint, in selection: CGRect) {
        let font = textFont
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let maxWidth = max(selection.maxX - point.x, 40)
        let maxHeight = max(selection.maxY - point.y, lineHeight)
        let editor = NSTextView(frame: CGRect(x: point.x, y: point.y, width: min(maxWidth, 120), height: lineHeight))
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0       // 让输入框里文字的位置和最终画出来的位置一致
        // 不自动换行（回车才换行），和导出时的画法一致；超出选区的部分同样会被裁掉
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.minSize = NSSize(width: min(maxWidth, 120), height: lineHeight)
        editor.maxSize = NSSize(width: maxWidth, height: maxHeight)
        editor.wantsLayer = true
        editor.layer?.borderWidth = 1
        editor.layer?.borderColor = NSColor.controlAccentColor.cgColor
        editor.layer?.cornerRadius = 2
        addSubview(editor, positioned: .below, relativeTo: toolbar)
        textEditor = editor
        applyStyleToTextEditor()
        window?.makeFirstResponder(editor)
    }

    private func applyStyleToTextEditor() {
        guard let editor = textEditor else { return }
        let color = NSColor(cgColor: annotation.color.cgColor()) ?? .red
        editor.font = textFont
        editor.textColor = color
        editor.insertionPointColor = color
        editor.typingAttributes = [.font: textFont, .foregroundColor: color]
    }

    private func discardTextEditor() {
        guard let editor = textEditor else { return }
        textEditor = nil
        editor.removeFromSuperview()
        window?.makeFirstResponder(self)
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        if let highlight = model.highlight {
            dim.appendRect(highlight)
            dim.windingRule = .evenOdd          // 高亮区域挖空，露出下面未变暗的定格画面
        }
        NSColor.black.withAlphaComponent(0.45).setFill()
        dim.fill()

        guard let highlight = model.highlight else { return }
        if let selection = model.selection, model.hasConfirmedSelection {
            drawAnnotations(in: selection)
        }

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: highlight.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = model.selection == nil ? 2 : 1
        border.stroke()

        guard let selection = model.selection else { return }
        if model.hasConfirmedSelection, !model.isLocked {       // 锁定期间不显示手柄
            for (_, point) in SelectionModel.handlePoints(for: selection) {
                let side = Self.handleSide
                let square = NSBezierPath(rect: CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side))
                NSColor.white.setFill()
                square.fill()
                NSColor.controlAccentColor.setStroke()
                square.stroke()
            }
        }
        drawSizeLabel(for: selection)
    }

    private func drawAnnotations(in selection: CGRect) {
        let inProgress = annotation.inProgress.map { [$0] } ?? []
        guard !annotation.items.isEmpty || !inProgress.isEmpty,
              let context = NSGraphicsContext.current?.cgContext
        else { return }
        let base = croppedBase(for: selection)
        context.saveGState()
        context.translateBy(x: selection.minX, y: selection.minY)      // 之后就是"选区内坐标"
        AnnotationRenderer.draw(annotation.items, in: context, selectionSize: selection.size, baseImage: base, cache: mosaicCache)
        AnnotationRenderer.draw(inProgress, in: context, selectionSize: selection.size, baseImage: base)   // 拖动中的不缓存
        context.restoreGState()
    }

    private func croppedBase(for selection: CGRect) -> CGImage? {
        if let baseCrop, baseCrop.selection == selection { return baseCrop.image }
        mosaicCache.removeAll()
        guard let image = ImageCropper.crop(snapshotImage, rect: selection, scale: imageScale) else { return nil }
        baseCrop = (selection, image)
        return image
    }

    private func drawSizeLabel(for selection: CGRect) {
        let text = "\(Int(selection.width)) × \(Int(selection.height))" as NSString
        let textSize = text.size(withAttributes: Self.labelAttributes)
        let labelSize = CGSize(width: textSize.width + 12, height: textSize.height + 6)
        let origin = ToolbarPlacement.labelOrigin(labelSize: labelSize, selection: selection, bounds: bounds)
        let background = NSBezierPath(roundedRect: CGRect(origin: origin, size: labelSize), xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        background.fill()
        text.draw(at: CGPoint(x: origin.x + 6, y: origin.y + 3), withAttributes: Self.labelAttributes)
    }

    private func refresh() {
        model.isLocked = annotation.locksSelection
        if model.hasConfirmedSelection, !model.isAdjusting, let selection = model.selection {
            toolbar.update(selectedTool: annotation.tool, canUndo: annotation.canUndo || textEditor != nil, canRedo: annotation.canRedo)
            toolbar.setFrameOrigin(ToolbarPlacement.toolbarOrigin(
                toolbarSize: toolbar.frame.size, selection: selection, bounds: bounds
            ))
            toolbar.isHidden = false
            if let tool = annotation.tool {
                styleBar.update(color: annotation.color, size: annotation.size, showsColors: tool.usesColor)
                styleBar.setFrameOrigin(ToolbarPlacement.styleBarOrigin(
                    barSize: styleBar.frame.size, toolbarFrame: toolbar.frame, selection: selection, bounds: bounds
                ))
                styleBar.isHidden = false
            } else {
                styleBar.isHidden = true
            }
        } else {
            toolbar.isHidden = true
            styleBar.isHidden = true
        }
        needsDisplay = true
    }

    // MARK: 鼠标

    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func local(_ point: CGPoint, in selection: CGRect) -> CGPoint {
        CGPoint(x: point.x - selection.minX, y: point.y - selection.minY)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = location(of: event)
        let before = model.highlight
        model.mouseMoved(to: point)
        updateCursor(at: point)
        if model.highlight != before { needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        // 鼠标移到了另一块屏：这块屏上的窗口高亮要熄掉（已有选区时 mouseMoved 本来就不起作用）
        let before = model.highlight
        model.mouseMoved(to: CGPoint(x: -1, y: -1))
        if model.highlight != before { needsDisplay = true }
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: location(of: event))
    }

    override func mouseDown(with event: NSEvent) {
        let point = location(of: event)
        window?.makeKey()
        delegate?.overlayViewDidBeginInteraction(self)

        if textEditor != nil {
            commitPendingText()                 // 点别处 = 完成文字输入（这一下不再画新的东西）
            return
        }
        if annotation.tool != nil, model.hasConfirmedSelection, let selection = model.selection {
            guard selection.contains(point) else { return }     // 选区锁定：选区外的点击不做任何事
            let shift = event.modifierFlags.contains(.shift)
            switch annotation.mouseDown(at: local(point, in: selection), in: selection.size, shift: shift) {
            case .beganDrag:
                isAnnotating = true
            case .beginText:
                beginTextEditing(at: point, in: selection)
            case .placedNumber, .ignored:
                break
            }
            refresh()
            return
        }
        if annotation.locksSelection { return }                 // 没选工具但已有标注：选区同样不能动，双击也不触发复制

        if event.clickCount == 2, model.hasConfirmedSelection, model.selection?.contains(point) == true {
            delegate?.overlayView(self, didRequest: .perform(.copy))      // 双击选区 = 复制
            return
        }
        model.mouseDown(at: point)
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = location(of: event)
        if isAnnotating, let selection = model.selection {
            annotation.mouseDragged(to: local(point, in: selection), shift: event.modifierFlags.contains(.shift))
            needsDisplay = true
            return
        }
        guard !annotation.locksSelection else { return }
        model.mouseDragged(to: point)
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        let point = location(of: event)
        if isAnnotating {
            isAnnotating = false
            if let selection = model.selection {
                annotation.mouseUp(at: local(point, in: selection), shift: event.modifierFlags.contains(.shift))
            }
            refresh()
            return
        }
        guard !annotation.locksSelection else { return }
        model.mouseUp(at: point)
        updateCursor(at: point)
        refresh()
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.overlayView(self, didRequest: .cancel)
    }

    private func updateCursor(at point: CGPoint) {
        if !toolbar.isHidden, toolbar.frame.contains(point) || (!styleBar.isHidden && styleBar.frame.contains(point)) {
            NSCursor.arrow.set()                   // 工具条 / 样式栏上用普通箭头
            return
        }
        let insideSelection = model.hasConfirmedSelection && model.selection?.contains(point) == true
        if annotation.locksSelection {
            if insideSelection, let tool = annotation.tool {
                (tool == .text ? NSCursor.iBeam : NSCursor.crosshair).set()
            } else {
                NSCursor.arrow.set()
            }
            return
        }
        if let handle = model.handle(at: point) {
            switch handle {
            case .left, .right: NSCursor.resizeLeftRight.set()
            case .top, .bottom: NSCursor.resizeUpDown.set()
            case .topLeft, .topRight, .bottomLeft, .bottomRight: NSCursor.crosshair.set()
            }
        } else if insideSelection {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }
}
