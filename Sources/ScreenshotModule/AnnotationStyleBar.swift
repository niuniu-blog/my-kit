import AppKit

/// 选中标注工具后出现在工具条旁边的样式栏：6 种颜色 + 3 档粗细。
final class AnnotationStyleBar: NSVisualEffectView {
    var onColor: ((AnnotationColor) -> Void)?
    var onSize: ((AnnotationSize) -> Void)?

    private let colors = AnnotationColor.allCases
    private let sizes = AnnotationSize.allCases
    private var colorButtons: [NSButton] = []
    private var sizeButtons: [NSButton] = []
    private let colorStack = NSStackView()
    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        state = .active
        blendingMode = .withinWindow
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        colorButtons = colors.enumerated().map { index, color in
            let button = NSButton(image: Self.swatch(color, selected: false), target: self, action: #selector(colorClicked(_:)))
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.tag = index
            button.toolTip = color.displayName
            return button
        }
        sizeButtons = sizes.enumerated().map { index, size in
            let button = NSButton(title: size.displayName, target: self, action: #selector(sizeClicked(_:)))
            button.bezelStyle = .accessoryBarAction
            button.setButtonType(.pushOnPushOff)
            button.tag = index
            return button
        }

        colorStack.orientation = .horizontal
        colorStack.spacing = 6
        colorButtons.forEach(colorStack.addArrangedSubview)
        let sizeStack = NSStackView(views: sizeButtons)
        sizeStack.orientation = .horizontal
        sizeStack.spacing = 4

        stack.orientation = .horizontal
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        stack.addArrangedSubview(colorStack)
        stack.addArrangedSubview(sizeStack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        update(color: .red, size: .medium, showsColors: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// showsColors = false：马赛克没有颜色可选，只显示粗细（= 方块大小）。
    func update(color: AnnotationColor, size: AnnotationSize, showsColors: Bool) {
        for (button, candidate) in zip(colorButtons, colors) {
            button.image = Self.swatch(candidate, selected: candidate == color)
        }
        for (button, candidate) in zip(sizeButtons, sizes) {
            button.state = candidate == size ? .on : .off
        }
        colorStack.isHidden = !showsColors
        setFrameSize(stack.fittingSize)
    }

    /// 颜色圆点；选中的外面多一圈白环。
    private static func swatch(_ color: AnnotationColor, selected: Bool) -> NSImage {
        NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
            let dot = NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4))
            (NSColor(cgColor: color.cgColor()) ?? .red).setFill()
            dot.fill()
            NSColor.white.withAlphaComponent(0.5).setStroke()      // 黑色圆点在深色底上也看得见
            dot.lineWidth = 0.5
            dot.stroke()
            if selected {
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1.25, dy: 1.25))
                NSColor.white.setStroke()
                ring.lineWidth = 1.5
                ring.stroke()
            }
            return true
        }
    }

    @objc private func colorClicked(_ sender: NSButton) {
        guard colors.indices.contains(sender.tag) else { return }
        onColor?(colors[sender.tag])
    }

    @objc private func sizeClicked(_ sender: NSButton) {
        guard sizes.indices.contains(sender.tag) else { return }
        onSize?(sizes[sender.tag])
    }
}
