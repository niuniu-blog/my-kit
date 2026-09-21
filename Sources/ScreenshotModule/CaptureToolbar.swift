import AppKit

/// 选区旁边的工具条：九种标注工具 | 撤销 重做 | 贴图 识别文字 保存 复制 取消。
final class CaptureToolbar: NSVisualEffectView {
    var onCommand: ((OverlayCommand) -> Void)?
    /// 点了某个标注工具（选中 / 再点一次取消，由 AnnotationModel 决定）
    var onToolToggle: ((AnnotationTool) -> Void)?

    private let tools = AnnotationTool.allCases
    private let actions: [(title: String, symbol: String, hint: String, command: OverlayCommand)] = [
        ("贴图", "pin", "贴在屏幕上  ⌘T", .perform(.pin)),
        ("识别文字", "text.viewfinder", "识别图中文字  ⌘R", .perform(.recognize)),
        ("保存", "square.and.arrow.down", "保存为 PNG 文件  ⌘S", .perform(.save)),
        ("复制", "doc.on.doc", "复制到剪切板  ↩", .perform(.copy)),
        ("", "xmark", "取消  Esc", .cancel),
    ]
    private var toolButtons: [NSButton] = []
    private var undoButton = NSButton()
    private var redoButton = NSButton()

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        state = .active
        blendingMode = .withinWindow
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        toolButtons = tools.enumerated().map { index, tool in
            let button = Self.iconButton(symbol: tool.symbolName, hint: tool.displayName, target: self, action: #selector(toolClicked(_:)))
            button.setButtonType(.pushOnPushOff)
            button.tag = index
            return button
        }
        undoButton = Self.iconButton(symbol: "arrow.uturn.backward", hint: "撤销  ⌘Z", target: self, action: #selector(undoClicked))
        redoButton = Self.iconButton(symbol: "arrow.uturn.forward", hint: "重做  ⇧⌘Z", target: self, action: #selector(redoClicked))
        let actionButtons = actions.enumerated().map { index, item -> NSButton in
            let image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.hint) ?? NSImage()
            let button = NSButton(title: item.title, image: image, target: self, action: #selector(actionClicked(_:)))
            button.tag = index
            button.bezelStyle = .accessoryBarAction
            button.imagePosition = item.title.isEmpty ? .imageOnly : .imageLeading
            button.toolTip = item.hint
            return button
        }

        var views: [NSView] = toolButtons
        views.append(Self.separator())
        views.append(contentsOf: [undoButton, redoButton])
        views.append(Self.separator())
        views.append(contentsOf: actionButtons)

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setFrameSize(stack.fittingSize)
        update(selectedTool: nil, canUndo: false, canRedo: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 按 AnnotationModel 的状态刷新：哪个工具高亮，撤销 / 重做是否可用。
    func update(selectedTool: AnnotationTool?, canUndo: Bool, canRedo: Bool) {
        for (button, tool) in zip(toolButtons, tools) {
            let selected = tool == selectedTool
            button.state = selected ? .on : .off
            button.contentTintColor = selected ? .controlAccentColor : nil
        }
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
    }

    private static func iconButton(symbol: String, hint: String, target: AnyObject, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: hint) ?? NSImage()
        let button = NSButton(image: image, target: target, action: action)
        button.bezelStyle = .accessoryBarAction
        button.imagePosition = .imageOnly
        button.toolTip = hint
        return button
    }

    private static func separator() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 18),
        ])
        return line
    }

    @objc private func toolClicked(_ sender: NSButton) {
        guard tools.indices.contains(sender.tag) else { return }
        onToolToggle?(tools[sender.tag])
    }

    @objc private func undoClicked() {
        onCommand?(.undo)
    }

    @objc private func redoClicked() {
        onCommand?(.redo)
    }

    @objc private func actionClicked(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        onCommand?(actions[sender.tag].command)
    }
}
