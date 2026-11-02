import Foundation

/// 分屏布局与标题。
public enum PaneLayout {
    public static let maxPanes = 9

    /// 每行几块：每行最多 2 块，从上往下排，块数是单数时最后一行只有 1 块。
    /// 1 → [1]，2 → [2]，3 → [2, 1]，4 → [2, 2]，5 → [2, 2, 1]
    public static func rows(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        if count == 1 { return [1] }
        var rows = Array(repeating: 2, count: count / 2)
        if count % 2 == 1 { rows.append(1) }
        return rows
    }

    /// 每块的标题 = 文件夹名；同名的从第二个起加序号：`api`、`api (2)`。
    public static func titles(forFolders paths: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return paths.map { path in
            let url = URL(fileURLWithPath: path)
            var name = url.lastPathComponent
            if name.isEmpty || name == "/" { name = path }
            let count = (seen[name] ?? 0) + 1
            seen[name] = count
            return count == 1 ? name : "\(name) (\(count))"
        }
    }
}
