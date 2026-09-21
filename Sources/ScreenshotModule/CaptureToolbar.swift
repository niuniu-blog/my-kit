import AppKit

/// 选区旁边的工具条：贴图 / 识别文字 / 保存 / 复制 / 取消。
final class CaptureToolbar: NSVisualEffectView {
    var onCommand: ((OverlayCommand) -> Void)?

    private let items: [(title: String, symbol: String, hint: String, command: OverlayCommand)] = [
        ("贴图", "pin", "贴在屏幕上  ⌘T", .perform(.pin)),
        ("识别文字", "text.viewfinder", "识别图中文字  ⌘R", .perform(.recognize)),
        ("保存", "square.and.arrow.down", "保存为 PNG 文件  ⌘S", .perform(.save)),
        ("复制", "doc.on.doc", "复制到剪切板  ↩", .perform(.copy)),
        ("", "xmark", "取消  Esc", .cancel),
    ]

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        state = .active
        blendingMode = .withinWindow
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        let buttons = items.enumerated().map { index, item -> NSButton in
            let image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.hint) ?? NSImage()
            let button = NSButton(title: item.title, image: image, target: self, action: #selector(buttonClicked(_:)))
            button.tag = index
            button.bezelStyle = .accessoryBarAction
            button.imagePosition = item.title.isEmpty ? .imageOnly : .imageLeading
            button.toolTip = item.hint
            return button
        }
        let stack = NSStackView(views: buttons)
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
        let size = stack.fittingSize
        setFrameSize(size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func buttonClicked(_ sender: NSButton) {
        guard items.indices.contains(sender.tag) else { return }
        onCommand?(items[sender.tag].command)
    }
}
