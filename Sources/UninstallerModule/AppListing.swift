import Foundation

/// 软件列表的搜索和排序。纯函数。
public enum AppListing {
    public enum SortOrder: String, CaseIterable, Identifiable, Sendable {
        case name
        case size

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .name: return "名称"
            case .size: return "大小"
            }
        }
    }

    /// 按显示名、软件名和 bundle id 做不区分大小写的包含匹配。空查询 = 全部。
    public static func filter(_ apps: [InstalledApp], query: String) -> [InstalledApp] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return apps }
        return apps.filter { app in
            app.title.lowercased().contains(needle)
                || app.identity.displayName.lowercased().contains(needle)
                || (app.identity.bundleID?.lowercased().contains(needle) ?? false)
        }
    }

    /// 名称：按本地化规则比较；大小：大的在前，还没算好的排最后。相同时按名称，保证顺序稳定。
    public static func sorted(_ apps: [InstalledApp], by order: SortOrder) -> [InstalledApp] {
        apps.sorted { first, second in
            if order == .size, first.sizeBytes != second.sizeBytes {
                switch (first.sizeBytes, second.sizeBytes) {
                case let (a?, b?): return a > b
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): break
                }
            }
            let comparison = first.title.localizedStandardCompare(second.title)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return first.id < second.id
        }
    }
}
