import Foundation

/// 软件列表里的一行。
public struct InstalledApp: Identifiable, Equatable, Sendable {
    public let identity: AppIdentity
    /// 列表里显示的名字（系统给的本地化名字，例如"微信"）
    public let title: String
    /// 占用空间；nil = 还没算好
    public var sizeBytes: UInt64?

    public var id: String { identity.url.path }

    public init(identity: AppIdentity, title: String, sizeBytes: UInt64? = nil) {
        self.identity = identity
        self.title = title
        self.sizeBytes = sizeBytes
    }

    /// 从一个 .app 路径构造；不是正常的软件时返回 nil。
    public init?(appURL: URL) {
        guard let identity = AppIdentity(appURL: appURL) else { return nil }
        self.init(identity: identity, title: Self.title(for: appURL, fallback: identity.displayName))
    }

    static func title(for url: URL, fallback: String) -> String {
        var name = FileManager.default.displayName(atPath: url.path)
        if name.lowercased().hasSuffix(".app") { name.removeLast(4) }
        return name.isEmpty ? fallback : name
    }
}

public struct InstalledAppList: Equatable, Sendable {
    /// 可以卸载的软件（受保护的已经排除）
    public var apps: [InstalledApp]
    /// 扫到的**全部**软件的 bundle id（含受保护的），用来避免误认别的软件的文件
    public var allBundleIDs: Set<String>

    public init(apps: [InstalledApp] = [], allBundleIDs: Set<String> = []) {
        self.apps = apps
        self.allBundleIDs = allBundleIDs
    }
}

/// 列出已安装的软件：各个根目录本身，以及它们的一级子文件夹。不进入 .app 内部。
public struct InstalledAppScanner: Sendable {
    public let roots: [URL]

    public init(roots: [URL]) {
        self.roots = roots
    }

    public static func standard() -> InstalledAppScanner {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return InstalledAppScanner(roots: [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
        ])
    }

    public func scan() -> InstalledAppList {
        var list = InstalledAppList()
        var seen = Set<String>()
        for root in roots {
            for child in children(of: root) {
                if child.pathExtension.lowercased() == "app" {
                    add(child, to: &list, seen: &seen)
                } else if isPlainDirectory(child) {
                    for grandchild in children(of: child) where grandchild.pathExtension.lowercased() == "app" {
                        add(grandchild, to: &list, seen: &seen)
                    }
                }
            }
        }
        return list
    }

    private func add(_ url: URL, to list: inout InstalledAppList, seen: inout Set<String>) {
        guard seen.insert(ProtectionRules.normalizedPath(url)).inserted else { return }
        guard let app = InstalledApp(appURL: url) else { return }
        if let bundleID = app.identity.bundleID { list.allBundleIDs.insert(bundleID) }
        if ProtectionRules.isProtectedApp(url: url, bundleID: app.identity.bundleID) { return }
        list.apps.append(app)
    }

    private func children(of directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.sorted().map { directory.appendingPathComponent($0) }
    }

    private func isPlainDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true && values?.isPackage != true
    }
}
