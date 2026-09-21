import Foundation

/// 一个待卸载软件的"身份"：用来在各个目录里认出哪些文件是它留下的。
public struct AppIdentity: Equatable, Sendable {
    /// .app 的路径（已标准化，不解析符号链接）
    public let url: URL
    public let bundleID: String?
    /// 显示名：CFBundleDisplayName → CFBundleName → 文件名
    public let displayName: String
    public let version: String?
    /// 用于按名称匹配的变体：全部小写、去重、长度 ≥ 3
    public let nameVariants: [String]
    /// bundle id 的第二段（厂商），小写；太短或太通用时为 nil。只用于"可能相关"
    public let vendorFragment: String?
    /// bundle id 的最后一段，小写；太短或太通用时为 nil。只用于"可能相关"
    public let lastIDSegment: String?

    /// 太通用、不能拿来当匹配依据的词
    static let genericWords: Set<String> = [
        "apple", "google", "microsoft", "github", "app", "mac", "macos", "company",
        "software", "desktop", "client", "helper", "agent", "launcher", "updater", "service",
    ]

    public init(url: URL, bundleID: String?, names: [String], version: String? = nil) {
        self.url = url.standardizedFileURL
        let trimmedID = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleID = (trimmedID?.isEmpty ?? true) ? nil : trimmedID
        let fileName = url.deletingPathExtension().lastPathComponent
        let cleaned = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.displayName = cleaned.first ?? fileName
        self.version = version
        self.nameVariants = Self.variants(from: cleaned + [fileName])

        let segments = (self.bundleID ?? "").lowercased().split(separator: ".").map(String.init)
        if segments.count >= 3, segments[1].count >= 4, !Self.genericWords.contains(segments[1]) {
            self.vendorFragment = segments[1]
        } else {
            self.vendorFragment = nil
        }
        if segments.count >= 2, let last = segments.last, last.count >= 4, !Self.genericWords.contains(last) {
            self.lastIDSegment = last
        } else {
            self.lastIDSegment = nil
        }
    }

    /// 从磁盘上的 .app 读取。不是以 .app 结尾的目录、或读不到 Info.plist 时返回 nil。
    public init?(appURL: URL) {
        var isDirectory: ObjCBool = false
        guard appURL.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: appURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let names = ["CFBundleDisplayName", "CFBundleName"].compactMap { plist[$0] as? String }
        self.init(
            url: appURL,
            bundleID: plist["CFBundleIdentifier"] as? String,
            names: names,
            version: plist["CFBundleShortVersionString"] as? String
        )
    }

    /// 每个名字本身 + 去掉空格的形式；小写、去重、丢掉长度 < 3 的（太短容易误伤）。
    static func variants(from names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in names {
            let lower = name.lowercased()
            for candidate in [lower, lower.replacingOccurrences(of: " ", with: "")] {
                guard candidate.count >= 3, seen.insert(candidate).inserted else { continue }
                result.append(candidate)
            }
        }
        return result
    }
}
