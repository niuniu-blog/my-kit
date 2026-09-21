import Foundation

/// 清单里的一条：软件本体，或者某个扫描位置下的一个文件 / 文件夹。
public struct LeftoverItem: Identifiable, Equatable, Sendable {
    public let url: URL
    public let category: String
    public let confidence: Confidence
    /// 当前用户没有权限移动它，需要交给访达（系统会弹管理员密码框）
    public let needsAdmin: Bool
    public let isAppBundle: Bool
    public let isBackgroundService: Bool
    public var sizeBytes: UInt64?

    public var id: String { url.path }

    public init(url: URL, category: String, confidence: Confidence, needsAdmin: Bool,
                isAppBundle: Bool = false, isBackgroundService: Bool = false, sizeBytes: UInt64? = nil) {
        self.url = url
        self.category = category
        self.confidence = confidence
        self.needsAdmin = needsAdmin
        self.isAppBundle = isAppBundle
        self.isBackgroundService = isBackgroundService
        self.sizeBytes = sizeBytes
    }
}

public struct LeftoverScanResult: Equatable, Sendable {
    public var items: [LeftoverItem]
    /// 存在但无权读取的位置（例如没有"完全磁盘访问权限"时的容器目录）
    public var unreadableLocations: [URL]

    public init(items: [LeftoverItem] = [], unreadableLocations: [URL] = []) {
        self.items = items
        self.unreadableLocations = unreadableLocations
    }
}

/// 在各个扫描位置的**一级**子项里找出和某个软件相关的东西。只读，不改动任何文件。
public struct LeftoverScanner: Sendable {
    public let locations: [ScanLocation]
    public let home: URL

    public init(locations: [ScanLocation], home: URL) {
        self.locations = locations
        self.home = home
    }

    public static func standard() -> LeftoverScanner {
        LeftoverScanner(locations: ScanLocation.standard(), home: FileManager.default.homeDirectoryForCurrentUser)
    }

    public var scanRoots: [URL] { locations.map(\.url) }

    public func scan(
        identity: AppIdentity,
        otherBundleIDs: Set<String> = [],
        isCancelled: () -> Bool = { false }
    ) -> LeftoverScanResult {
        let fileManager = FileManager.default
        let roots = scanRoots
        var result = LeftoverScanResult()
        var seen = Set<String>()

        // 软件本体永远排第一条
        result.items.append(LeftoverItem(
            url: identity.url, category: "软件本体", confidence: .certain,
            needsAdmin: Self.needsAdmin(identity.url), isAppBundle: true))
        seen.insert(ProtectionRules.normalizedPath(identity.url))

        for location in locations {
            if isCancelled() { return result }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: location.url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue                                        // 位置不存在：跳过
            }
            guard let names = try? fileManager.contentsOfDirectory(atPath: location.url.path) else {
                result.unreadableLocations.append(location.url)   // 存在但读不了
                continue
            }
            for name in names {
                // 主目录这个位置只看隐藏项；普通文件夹（文稿、下载……）不归卸载器管
                if location.kind == .hidden, ProtectionRules.normalizedPath(location.url) == ProtectionRules.normalizedPath(home),
                   !name.hasPrefix(".") {
                    continue
                }
                guard let confidence = LeftoverMatcher.match(
                    fileName: name, kind: location.kind, identity: identity, otherBundleIDs: otherBundleIDs)
                else { continue }

                let url = location.url.appendingPathComponent(name)
                if ProtectionRules.isForbiddenPath(url, home: home, scanRoots: roots) { continue }
                guard seen.insert(ProtectionRules.normalizedPath(url)).inserted else { continue }

                result.items.append(LeftoverItem(
                    url: url, category: location.category, confidence: confidence,
                    needsAdmin: Self.needsAdmin(url), isBackgroundService: location.isBackgroundService))
            }
        }
        return result
    }

    /// 移到废纸篓需要：能改父目录；如果它自己是目录，还要能改它自己（搬目录要更新它的 ".."）。
    static func needsAdmin(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        let parent = url.deletingLastPathComponent().path
        if !fileManager.isWritableFile(atPath: parent) { return true }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values?.isDirectory == true, values?.isSymbolicLink != true, !fileManager.isWritableFile(atPath: url.path) {
            return true
        }
        return false
    }
}
