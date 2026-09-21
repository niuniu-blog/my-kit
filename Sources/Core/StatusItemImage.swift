import AppKit

/// 把"图标 + 右边的（多行）小字"画成一张菜单栏图片。
/// 系统的状态栏按钮排不好两行文字（垂直位置不可控），所以自己画：位置、对齐都由这里决定。
@MainActor
public enum StatusItemImage {
    /// 菜单栏内容区的高度
    public static let height: CGFloat = 22
    public static let gap: CGFloat = 4
    public static let symbolPointSize: CGFloat = 14

    public struct Layout: Equatable {
        public let size: CGSize
        public let iconRect: CGRect
        public let textRect: CGRect
    }

    /// 图标靠左，文字在右；两者都垂直居中。文字宽高向上取整，避免半个像素造成模糊。
    public static func layout(iconSize: CGSize, textSize: CGSize) -> Layout {
        let textWidth = ceil(textSize.width)
        let textHeight = min(ceil(textSize.height), height)
        let width = iconSize.width + (textWidth > 0 ? gap + textWidth : 0)
        return Layout(
            size: CGSize(width: width, height: height),
            iconRect: CGRect(x: 0, y: ((height - iconSize.height) / 2).rounded(), width: iconSize.width, height: iconSize.height),
            textRect: CGRect(x: textWidth > 0 ? iconSize.width + gap : iconSize.width,
                             y: ((height - textHeight) / 2).rounded(), width: textWidth, height: textHeight)
        )
    }

    /// text 里没有任何颜色 → 返回模板图（系统按深 / 浅色菜单栏自动着色，永远正确）；
    /// 有颜色（≥ 85% 的红色告警）→ 返回彩色图，其余部分用 labelColor，在真正绘制时按当时的外观解析。
    public static func compose(symbolName: String, text: NSAttributedString?) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MyKit")?
            .withSymbolConfiguration(configuration) else { return nil }

        let text = (text?.length ?? 0) > 0 ? text : nil
        let textSize = text?.boundingRect(with: NSSize(width: 2000, height: height), options: [.usesLineFragmentOrigin]).size ?? .zero
        let layout = layout(iconSize: symbol.size, textSize: textSize)
        let isColored = text.map(hasColor) ?? false

        let image = NSImage(size: layout.size, flipped: false) { _ in
            let base: NSColor = isColored ? .labelColor : .black
            // 模板图：符号本身就是黑色，整张图交给系统按菜单栏深浅着色。
            // 彩色图（有红色告警）：用符号的调色板配置染成 labelColor，在绘制时按当时的外观解析。
            // 不用 sourceAtop 之类的合成模式：图片若被直接画到目标上，会连背景一起涂掉。
            if isColored, let tinted = symbol.withSymbolConfiguration(
                configuration.applying(NSImage.SymbolConfiguration(paletteColors: [base]))) {
                tinted.draw(in: layout.iconRect)
            } else {
                symbol.draw(in: layout.iconRect)
            }

            if let text {
                let drawn = NSMutableAttributedString(attributedString: text)
                drawn.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: drawn.length)) { value, range, _ in
                    if value == nil { drawn.addAttribute(.foregroundColor, value: base, range: range) }
                }
                drawn.draw(with: layout.textRect, options: [.usesLineFragmentOrigin])
            }
            return true
        }
        image.isTemplate = !isColored
        return image
    }

    private static func hasColor(_ text: NSAttributedString) -> Bool {
        var found = false
        text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if value != nil { found = true; stop.pointee = true }
        }
        return found
    }
}
