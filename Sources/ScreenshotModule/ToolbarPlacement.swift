import CoreGraphics

/// 工具条和尺寸标签放在哪。纯函数，屏内坐标（左上角原点），返回的是左上角位置。
public enum ToolbarPlacement {
    /// 优先选区下方右对齐；下方放不下 → 上方；上下都放不下 → 选区内右下角。水平方向始终不超出屏幕。
    public static func toolbarOrigin(toolbarSize: CGSize, selection: CGRect, bounds: CGRect, gap: CGFloat = 8) -> CGPoint {
        func clampedX(_ x: CGFloat) -> CGFloat {
            min(max(x, bounds.minX), max(bounds.minX, bounds.maxX - toolbarSize.width))
        }
        let below = selection.maxY + gap
        if below + toolbarSize.height <= bounds.maxY {
            return CGPoint(x: clampedX(selection.maxX - toolbarSize.width), y: below)
        }
        let above = selection.minY - gap - toolbarSize.height
        if above >= bounds.minY {
            return CGPoint(x: clampedX(selection.maxX - toolbarSize.width), y: above)
        }
        return CGPoint(
            x: clampedX(selection.maxX - gap - toolbarSize.width),
            y: selection.maxY - gap - toolbarSize.height
        )
    }

    /// 尺寸标签：选区左上角外侧；上方放不下就放到选区内侧。
    public static func labelOrigin(labelSize: CGSize, selection: CGRect, bounds: CGRect, gap: CGFloat = 4) -> CGPoint {
        let x = min(max(selection.minX, bounds.minX), max(bounds.minX, bounds.maxX - labelSize.width))
        let outside = selection.minY - gap - labelSize.height
        if outside >= bounds.minY {
            return CGPoint(x: x, y: outside)
        }
        return CGPoint(x: x + gap, y: selection.minY + gap)
    }

    /// 识别结果面板放在选区旁边，方便对照原图：右 → 左 → 下 → 上 → 选区内右下角。始终完整落在屏幕内。
    public static func sidePanelOrigin(panelSize: CGSize, selection: CGRect, bounds: CGRect, gap: CGFloat = 12) -> CGPoint {
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, bounds.minX), max(bounds.maxX - panelSize.width, bounds.minX)) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, bounds.minY), max(bounds.maxY - panelSize.height, bounds.minY)) }

        let right = selection.maxX + gap
        if right + panelSize.width <= bounds.maxX {
            return CGPoint(x: right, y: clampY(selection.minY))
        }
        let left = selection.minX - gap - panelSize.width
        if left >= bounds.minX {
            return CGPoint(x: left, y: clampY(selection.minY))
        }
        let below = selection.maxY + gap
        if below + panelSize.height <= bounds.maxY {
            return CGPoint(x: clampX(selection.minX), y: below)
        }
        let above = selection.minY - gap - panelSize.height
        if above >= bounds.minY {
            return CGPoint(x: clampX(selection.minX), y: above)
        }
        return CGPoint(
            x: clampX(min(selection.maxX, bounds.maxX) - gap - panelSize.width),
            y: clampY(min(selection.maxY, bounds.maxY) - gap - panelSize.height)
        )
    }
}
