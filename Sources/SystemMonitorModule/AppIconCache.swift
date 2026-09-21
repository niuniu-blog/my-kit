import AppKit
import UniformTypeIdentifiers

/// 排行榜里每个软件的显示名和 16pt 图标。按分组键缓存，模块存活期间有效（也就几十个小图标）。
@MainActor
final class AppIconCache {
    struct Entry {
        let name: String
        let icon: NSImage
    }

    static let iconSize = NSSize(width: 16, height: 16)

    private var cache: [String: Entry] = [:]
    /// 不在 .app 里的进程（node、java 之类）用系统的"可执行文件"图标
    private lazy var genericIcon: NSImage = Self.sized(NSWorkspace.shared.icon(for: .unixExecutable))

    func entry(for group: AppGroup) -> Entry {
        if let cached = cache[group.key] { return cached }
        let entry: Entry
        if let bundlePath = group.bundlePath, FileManager.default.fileExists(atPath: bundlePath) {
            var name = FileManager.default.displayName(atPath: bundlePath)      // 本地化的名字，如"微信"
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            entry = Entry(
                name: name.isEmpty ? group.fallbackName : name,
                icon: Self.sized(NSWorkspace.shared.icon(forFile: bundlePath))
            )
        } else {
            entry = Entry(name: group.fallbackName, icon: genericIcon)
        }
        cache[group.key] = entry
        return entry
    }

    private static func sized(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = iconSize
        return copy
    }
}
