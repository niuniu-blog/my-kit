import Foundation

/// 分屏布局与标题。
public enum PaneLayout {
    public static let maxPanes = 9

    public static let maxPerRow = 3

    /// 每行几块：从左往右、从上往下排，每行排满 3 块再换下一行，最后一行放剩下的。
    /// 列表里的顺序就是这个顺序。1 → [1]，3 → [3]，4 → [3, 1]，5 → [3, 2]，9 → [3, 3, 3]
    public static func rows(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var rows = Array(repeating: maxPerRow, count: count / maxPerRow)
        if count % maxPerRow > 0 { rows.append(count % maxPerRow) }
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
