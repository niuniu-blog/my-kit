import AppKit

/// 按 bundle id 查找来源 App 的图标并缓存，供面板列表显示"从哪里复制的"。
@MainActor
final class AppIconProvider {
    static let shared = AppIconProvider()

    /// 来源未知、或来源 App 已被卸载时使用
    let fallback: NSImage
    private var cache: [String: NSImage] = [:]

    init() {
        fallback = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "未知应用") ?? NSImage()
    }

    func icon(forBundleID bundleID: String?) -> NSImage {
        guard let bundleID, !bundleID.isEmpty else { return fallback }
        if let cached = cache[bundleID] { return cached }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = fallback
        }
        cache[bundleID] = image
        return image
    }
}
