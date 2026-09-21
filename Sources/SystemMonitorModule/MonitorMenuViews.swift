import AppKit

/// 菜单里监控部分的宽度。自定义视图的菜单项需要自己定宽。
enum MonitorMenuMetrics {
    static let width: CGFloat = 300
    static let headerHeight: CGFloat = 24
    static let rowHeight: CGFloat = 20
    static let leftInset: CGFloat = 14
    static let rightInset: CGFloat = 14
}

/// 标题行：「CPU   42%      用户 35%   系统 7%」/「内存  63%      10.1 / 16 GB」
final class MonitorHeaderView: NSView {
    let titleLabel = NSTextField(labelWithString: "")
    let valueLabel = NSTextField(labelWithString: "--")
    let detailLabel = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: MonitorMenuMetrics.width, height: MonitorMenuMetrics.headerHeight))
        let height: CGFloat = 17
        let y = (MonitorMenuMetrics.headerHeight - height) / 2

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: MonitorMenuMetrics.leftInset, y: y, width: 40, height: height)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.frame = NSRect(x: titleLabel.frame.maxX + 4, y: y, width: 48, height: height)

        detailLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .right
        let detailX = valueLabel.frame.maxX + 4
        detailLabel.frame = NSRect(x: detailX, y: y, width: MonitorMenuMetrics.width - MonitorMenuMetrics.rightInset - detailX, height: height)

        for label in [titleLabel, valueLabel, detailLabel] {
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func update(value: String, detail: String, isWarning: Bool) {
        valueLabel.stringValue = value
        valueLabel.textColor = isWarning ? .systemRed : .labelColor
        detailLabel.stringValue = detail
    }
}

/// 排行行：图标 + 软件名 + 右对齐的数值。也用来显示"正在统计…"这类占位文字。
final class MonitorRowView: NSView {
    let iconView = NSImageView()
    let nameLabel = NSTextField(labelWithString: "")
    let valueLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: MonitorMenuMetrics.width, height: MonitorMenuMetrics.rowHeight))
        let height: CGFloat = 16
        let y = (MonitorMenuMetrics.rowHeight - height) / 2
        let iconX = MonitorMenuMetrics.leftInset + 10

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.frame = NSRect(x: iconX, y: y, width: 16, height: 16)

        let valueWidth: CGFloat = 72
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(
            x: MonitorMenuMetrics.width - MonitorMenuMetrics.rightInset - valueWidth, y: y, width: valueWidth, height: height)

        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        let nameX = iconView.frame.maxX + 6
        nameLabel.frame = NSRect(x: nameX, y: y, width: valueLabel.frame.minX - 6 - nameX, height: height)

        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(valueLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show(icon: NSImage, name: String, value: String) {
        iconView.image = icon
        nameLabel.stringValue = name
        nameLabel.textColor = .labelColor
        valueLabel.stringValue = value
    }

    /// 没有图标和数值的一行灰字，如"正在统计…"
    func showPlaceholder(_ text: String) {
        iconView.image = nil
        nameLabel.stringValue = text
        nameLabel.textColor = .secondaryLabelColor
        valueLabel.stringValue = ""
    }
}
