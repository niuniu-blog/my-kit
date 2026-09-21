import Foundation

/// 卸载器的安全规则：哪些软件不能卸载、哪些路径永远不能动、执行前的最后一次复核。
public enum ProtectionRules {
    public static let ownBundleID = "com.imiros.mykit"

    /// 主目录下永远不碰的隐藏项（密钥、命令行配置、废纸篓本身等）
    static let sensitiveHomeNames: Set<String> = [
        ".Trash", ".ssh", ".gnupg", ".zshrc", ".zprofile", ".zshenv", ".zsh_history", ".zsh_sessions",
        ".bashrc", ".bash_profile", ".bash_history", ".profile", ".gitconfig", ".netrc",
        ".config", ".cache", ".local", ".DS_Store", ".CFUserTextEncoding",
    ]

    /// 这些目录本身永远不能被移走（它们下面的具体条目另行判断）
    /// 路径一律先经过 normalizedPath（去掉 /private 前缀）再和这张表比较。
    static let forbiddenExactPaths: Set<String> = [
        "/", "/Applications", "/Applications/Utilities", "/Library", "/Users", "/Volumes", "/private",
        "/var", "/var/db", "/var/db/receipts", "/var/folders", "/tmp", "/etc", "/opt", "/cores",
    ]

    /// 这些目录及其下面的一切都不能动
    static let forbiddenPrefixes: [String] = ["/System", "/usr", "/bin", "/sbin"]

    // MARK: 软件

    /// 系统软件、MyKit 自己、不是正常 .app 目录的东西，一律不可卸载。
    public static func isProtectedApp(url: URL, bundleID: String?) -> Bool {
        let standardized = url.standardizedFileURL
        let path = normalizedPath(url)
        if path == "/System" || path.hasPrefix("/System/") { return true }
        if let id = bundleID?.lowercased() {
            if id.hasPrefix("com.apple.") { return true }
            if id == ownBundleID { return true }
        }
        if path == normalizedPath(Bundle.main.bundleURL) { return true }
        guard standardized.pathExtension.lowercased() == "app" else { return true }

        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if values?.isSymbolicLink == true { return true }
        if values?.isDirectory != true { return true }
        return false
    }

    // MARK: 路径

    /// 用于比较的规范路径：解析 `..`（不解析符号链接），并把 /private/var、/private/tmp、/private/etc
    /// 统一成 /var、/tmp、/etc —— 系统对"已存在"和"不存在"的路径处理不一致，这里抹平。
    public static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        for alias in ["/var", "/tmp", "/etc"] where path == "/private" + alias || path.hasPrefix("/private" + alias + "/") {
            path.removeFirst("/private".count)
        }
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    public static func isForbiddenPath(_ url: URL, home: URL, scanRoots: [URL] = []) -> Bool {
        let path = normalizedPath(url)
        if path.isEmpty { return true }
        if path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) { return true }   // 控制字符、换行
        if forbiddenExactPaths.contains(path) { return true }
        for prefix in forbiddenPrefixes where path == prefix || path.hasPrefix(prefix + "/") { return true }

        let homePath = normalizedPath(home)
        if path == homePath || path == homePath + "/Library" { return true }
        if homePath.hasPrefix(path + "/") { return true }                       // 主目录的任何上级
        if normalizedPath(url.deletingLastPathComponent()) == homePath,
           sensitiveHomeNames.contains(url.lastPathComponent) {
            return true
        }
        for root in scanRoots where normalizedPath(root) == path { return true }   // 扫描位置本身
        return false
    }

    public enum RemovalCheck: Equatable {
        case allowed
        case rejected(String)
    }

    /// 执行前对每一条的最后复核：要么是软件本体，要么它的父目录恰好是某个扫描位置。
    public static func checkRemoval(of url: URL, appURL: URL, appBundleID: String?, scanRoots: [URL], home: URL) -> RemovalCheck {
        let target = url.standardizedFileURL
        let name = target.lastPathComponent
        if name.isEmpty || name == "." || name == ".." {
            return .rejected("路径不在允许范围内")
        }
        if isForbiddenPath(target, home: home, scanRoots: scanRoots) {
            return .rejected("路径不在允许范围内")
        }
        if normalizedPath(target) == normalizedPath(appURL) {
            return isProtectedApp(url: appURL, bundleID: appBundleID) ? .rejected("这是系统软件，不能卸载") : .allowed
        }
        let parent = normalizedPath(target.deletingLastPathComponent())
        if scanRoots.contains(where: { normalizedPath($0) == parent }) {
            return .allowed
        }
        return .rejected("路径不在允许范围内")
    }
}
