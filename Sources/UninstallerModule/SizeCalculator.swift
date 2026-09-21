import Foundation

public enum SizeCalculator {
    /// 一个文件或整个目录实际占用的磁盘空间。不跟随符号链接。被取消时返回 nil。
    public static func allocatedSize(of url: URL, isCancelled: () -> Bool = { false }) -> UInt64? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory != true || values.isSymbolicLink == true {
            return UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true })
        else { return 0 }

        var total: UInt64 = 0
        var visited = 0
        for case let item as URL in enumerator {
            visited += 1
            if visited % 256 == 0, isCancelled() { return nil }
            guard let itemValues = try? item.resourceValues(forKeys: keys) else { continue }
            total += UInt64(itemValues.totalFileAllocatedSize ?? itemValues.fileAllocatedSize ?? 0)
        }
        return isCancelled() ? nil : total
    }

    /// "3.2 GB" / "850 MB" / "12 KB"（1 GB = 1024³ 字节，与系统监控的写法一致）。
    public static func format(_ bytes: UInt64) -> String {
        let kilobyte = 1024.0
        let megabyte = kilobyte * 1024
        let gigabyte = megabyte * 1024
        let value = Double(bytes)
        if value >= gigabyte {
            return String(format: "%.1f GB", value / gigabyte)
        }
        if value >= megabyte {
            return String(format: "%.0f MB", value / megabyte)
        }
        if bytes == 0 {
            return "0 KB"
        }
        return String(format: "%.0f KB", max(1, (value / kilobyte).rounded()))
    }
}
