import AppKit

@MainActor
protocol OverlayViewDelegate: AnyObject {
    /// 用户开始在这块屏上操作（其他屏的选区要清掉）
    func overlayViewDidBeginInteraction(_ view: OverlayView)
    func overlayView(_ view: OverlayView, didRequest command: OverlayCommand)
}

/// 盖在定格画面上面的那一层：画暗层、高亮 / 选区、手柄、尺寸标签，并把鼠标事件交给 SelectionModel。
/// isFlipped = true，所以视图坐标就是"屏内坐标"（左上角原点）。
final class OverlayView: NSView {
    weak var delegate: OverlayViewDelegate?
    private(set) var model: SelectionModel
    private let toolbar = CaptureToolbar()

    private static let handleSide: CGFloat = 8
    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    init(frame: NSRect, windows: [CGRect]) {
        model = SelectionModel(bounds: CGRect(origin: .zero, size: frame.size), windows: windows)
        super.init(frame: frame)
        toolbar.isHidden = true
        toolbar.onCommand = { [weak self] command in
            guard let self else { return }
            self.delegate?.overlayView(self, didRequest: command)
        }
        addSubview(toolbar)
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

    /// Esc / 右键的第一级：清掉这块屏上的选区。返回 true 表示这里本来就没有东西可清。
    func cancelSelection() -> Bool {
        let nothingToCancel = model.cancel()
        refresh()
        return nothingToCancel
    }

    func resetSelection() {
        model.reset()
        refresh()
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
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: highlight.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = model.selection == nil ? 2 : 1
        border.stroke()

        guard let selection = model.selection else { return }
        if model.hasConfirmedSelection {
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
        if model.hasConfirmedSelection, !model.isAdjusting, let selection = model.selection {
            toolbar.setFrameOrigin(ToolbarPlacement.toolbarOrigin(
                toolbarSize: toolbar.frame.size, selection: selection, bounds: bounds
            ))
            toolbar.isHidden = false
        } else {
            toolbar.isHidden = true
        }
        needsDisplay = true
    }

    // MARK: 鼠标

    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
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
        if event.clickCount == 2, model.hasConfirmedSelection, model.selection?.contains(point) == true {
            delegate?.overlayView(self, didRequest: .perform(.copy))      // 双击选区 = 复制
            return
        }
        model.mouseDown(at: point)
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        model.mouseDragged(to: location(of: event))
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        let point = location(of: event)
        model.mouseUp(at: point)
        updateCursor(at: point)
        refresh()
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.overlayView(self, didRequest: .cancel)
    }

    private func updateCursor(at point: CGPoint) {
        if !toolbar.isHidden, toolbar.frame.contains(point) {
            NSCursor.arrow.set()                   // 工具条上用普通箭头
            return
        }
        if let handle = model.handle(at: point) {
            switch handle {
            case .left, .right: NSCursor.resizeLeftRight.set()
            case .top, .bottom: NSCursor.resizeUpDown.set()
            case .topLeft, .topRight, .bottomLeft, .bottomRight: NSCursor.crosshair.set()
            }
        } else if model.hasConfirmedSelection, model.selection?.contains(point) == true {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }
}
