import Foundation

/// 一个文件和待卸载软件的关系有多确定。
public enum Confidence: Int, Sendable, Equatable {
    /// 确定相关：名字里带着这个软件独有的标识，默认勾选
    case certain
    /// 可能相关：只是同名或名字沾边，默认不勾选，由用户自己判断
    case possible
}

/// 只看名字的匹配规则。纯函数，不碰文件系统。
public enum LeftoverMatcher {
    /// 比较前先去掉的后缀（小写）
    static let strippedSuffixes = [".plist", ".savedstate", ".binarycookies", ".bom", ".log", ".crash", ".ips", ".diag"]

    /// - otherBundleIDs: 机器上**其他**已安装软件的 bundle id。名字如果更像是它们的东西
    ///   （例如卸载 Chrome 时遇到 com.google.Chrome.canary 的文件），就不算在这个软件头上。
    public static func match(
        fileName: String,
        kind: ScanLocation.Kind,
        identity: AppIdentity,
        otherBundleIDs: Set<String> = []
    ) -> Confidence? {
        var name = fileName.lowercased()
        for suffix in strippedSuffixes where name.hasSuffix(suffix) && name.count > suffix.count {
            name.removeLast(suffix.count)
            break
        }
        guard !name.isEmpty else { return nil }
        if name.hasPrefix("com.apple.") { return nil }                 // Apple 自己的数据永远不碰

        let bundleID = identity.bundleID?.lowercased()
        if belongsToAnotherApp(name, own: bundleID, others: otherBundleIDs) { return nil }

        // —— 确定相关 ——
        if let bundleID {
            if name == bundleID || name.hasPrefix(bundleID + ".") { return .certain }
            if name.hasSuffix("." + bundleID) || name.contains("." + bundleID + ".") { return .certain }
        }
        if kind == .byName, identity.nameVariants.contains(name) { return .certain }
        if kind == .crashReports,
           identity.nameVariants.contains(where: { name.hasPrefix($0 + "_") || name.hasPrefix($0 + "-") }) {
            return .certain
        }

        // —— 可能相关 ——
        let bare = name.hasPrefix(".") ? String(name.dropFirst()) : name
        if kind == .hidden, identity.nameVariants.contains(bare) { return .possible }
        if let vendor = identity.vendorFragment, bare == vendor { return .possible }
        if let segment = identity.lastIDSegment, containsWord(name, segment) { return .possible }
        if identity.nameVariants.contains(where: { $0.count >= 4 && containsWord(name, $0) }) { return .possible }
        return nil
    }

    /// word 是否作为一个"完整的词"出现在 text 里：前后不能紧挨着字母或数字。
    /// 这样卸载 "Code" 时不会把 "Xcode" 的东西列出来。
    static func containsWord(_ text: String, _ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        var searchStart = text.startIndex
        while let range = text.range(of: word, range: searchStart..<text.endIndex) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            let boundedBefore = before.map { !($0.isLetter || $0.isNumber) } ?? true
            let boundedAfter = after.map { !($0.isLetter || $0.isNumber) } ?? true
            if boundedBefore && boundedAfter { return true }
            searchStart = text.index(after: range.lowerBound)
        }
        return false
    }

    /// 名字是否更具体地指向另一个已安装的软件。
    static func belongsToAnotherApp(_ name: String, own: String?, others: Set<String>) -> Bool {
        for other in others {
            let otherID = other.lowercased()
            if otherID == own || otherID.isEmpty { continue }
            let matchesOther = name == otherID || name.hasPrefix(otherID + ".")
                || name.hasSuffix("." + otherID) || name.contains("." + otherID + ".")
            guard matchesOther else { continue }
            // 另一个软件的 id 比自己的更长（更具体），或者自己的 id 根本不出现在名字里 → 归它
            if let own, name.contains(own), otherID.count <= own.count { continue }
            return true
        }
        return false
    }
}
