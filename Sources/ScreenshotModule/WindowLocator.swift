import CoreGraphics
import Foundation

/// 找出屏幕上的窗口边框，用于"鼠标移到窗口上自动高亮"。
/// 读取窗口边框不需要"屏幕录制"授权（读取窗口标题才需要，这里不读）。
public enum WindowLocator {
    /// 小于这个尺寸的窗口（各种小浮层）不参与识别
    public static let minimumWindowSide: CGFloat = 40

    /// CG 全局坐标（主屏左上角为原点、y 向下）→ 某块屏的屏内坐标，并裁到屏幕范围内。
    /// 窗口完全不在这块屏上时返回 nil。
    public static func localRect(cgBounds: CGRect, displayBounds: CGRect) -> CGRect? {
        let clipped = cgBounds.intersection(displayBounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        return clipped.offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY)
    }

    /// 批量换算，保持前后顺序（数组靠前 = 窗口靠前）。
    public static func localRects(cgWindows: [CGRect], displayBounds: CGRect) -> [CGRect] {
        cgWindows.compactMap { localRect(cgBounds: $0, displayBounds: displayBounds) }
    }

    /// 鼠标位置下最靠前的窗口。
    public static func topWindow(at point: CGPoint, in windows: [CGRect]) -> CGRect? {
        windows.first { $0.contains(point) }
    }

    /// 从 CGWindowListCopyWindowInfo 的结果里挑出普通窗口的边框（CG 全局坐标），保持前后顺序。
    public static func parse(_ list: [[String: Any]], excludingPID ownPID: pid_t) -> [CGRect] {
        list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0 else { return nil }          // 只要普通窗口层
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 { return nil }
            if let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == ownPID { return nil }   // 不识别 MyKit 自己的窗口
            guard let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else { return nil }
            guard bounds.width >= minimumWindowSide, bounds.height >= minimumWindowSide else { return nil }
            return bounds
        }
    }

    /// 当前屏幕上所有可见的普通窗口（CG 全局坐标，前 → 后）。
    public static func visibleWindowBounds() -> [CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
        return parse(list, excludingPID: ProcessInfo.processInfo.processIdentifier)
    }
}
