import Foundation

/// 排行榜里的一项"软件"：同一个 .app 里的所有进程（含辅助进程）算作一组。
public struct AppGroup: Hashable, Sendable {
    /// 分组键：.app 包的路径，或者（不在 .app 里的进程）可执行文件名
    public let key: String
    /// 取不到本地化显示名时用的名字
    public let fallbackName: String
    /// .app 包的路径；不在 .app 里的进程为 nil
    public let bundlePath: String?

    public init(key: String, fallbackName: String, bundlePath: String?) {
        self.key = key
        self.fallbackName = fallbackName
        self.bundlePath = bundlePath
    }
}

public enum ProcessGrouping {
    /// 可执行文件路径 → 所属的软件。路径为空返回 nil。
    /// 路径里有 `.app/` 就取**最外层**的 .app（Chrome 的几十个 Helper 都在 Google Chrome.app 里面）。
    public static func group(forPath path: String) -> AppGroup? {
        guard !path.isEmpty else { return nil }
        if let range = path.range(of: ".app/") {
            let bundlePath = String(path[..<range.lowerBound]) + ".app"
            let fileName = (bundlePath as NSString).lastPathComponent
            let name = String(fileName.dropLast(4))
            return AppGroup(key: bundlePath, fallbackName: name.isEmpty ? fileName : name, bundlePath: bundlePath)
        }
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty else { return nil }
        return AppGroup(key: name, fallbackName: name, bundlePath: nil)
    }
}
