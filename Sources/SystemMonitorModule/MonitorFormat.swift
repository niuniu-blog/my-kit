import Foundation

/// 监控数字的显示格式。纯函数。
public enum MonitorFormat {
    /// 总占用达到这个百分比（按显示出来的整数算）时标红
    public static let warningThreshold = 85
    private static let gigabyte = 1_073_741_824.0
    private static let megabyte = 1_048_576.0

    /// 总占用：四舍五入成整数，夹在 0…100；nil（还没有数据 / 读取失败）显示 "--"。
    public static func percent(_ value: Double?) -> String {
        guard let rounded = roundedPercent(value) else { return "--" }
        return "\(rounded)%"
    }

    /// 单个软件的 CPU：保留 1 位小数，可以超过 100。
    public static func percentOneDecimal(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    /// ≥ 1 GB 显示 "3.2 GB"，否则 "850 MB"。1 GB = 1024³ 字节。
    public static func bytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= gigabyte {
            return String(format: "%.1f GB", value / gigabyte)
        }
        return "\(Int((value / megabyte).rounded())) MB"
    }

    /// "10.1 / 16 GB"；总量是整数 GB 时不带小数。
    public static func memorySummary(usedBytes: UInt64, totalBytes: UInt64) -> String {
        let used = String(format: "%.1f", Double(usedBytes) / gigabyte)
        let totalValue = Double(totalBytes) / gigabyte
        let total = totalValue == totalValue.rounded() ? "\(Int(totalValue))" : String(format: "%.1f", totalValue)
        return "\(used) / \(total) GB"
    }

    public static func isWarning(_ value: Double?) -> Bool {
        guard let rounded = roundedPercent(value) else { return false }
        return rounded >= warningThreshold
    }

    /// 菜单栏标题的一段：文字 + 是否标红。
    public struct TitleSegment: Equatable, Sendable {
        public let text: String
        public let isWarning: Bool

        public init(text: String, isWarning: Bool) {
            self.text = text
            self.isWarning = isWarning
        }
    }

    /// "CPU 12%  内存 63%" 拆成四段，只有数字那两段可能标红。
    /// 菜单栏上的两行小字。第一行 CPU（+ 下载速度），第二行内存（+ 上传速度）。
    /// 文字里的 "\t" 是列分隔：第二列（网速）在两行里左对齐。
    public static func titleLines(cpu: Double?, memory: Double?, network: NetworkSpeed?) -> [[TitleSegment]] {
        var first = [TitleSegment(text: "CPU ", isWarning: false), TitleSegment(text: percent(cpu), isWarning: isWarning(cpu))]
        var second = [TitleSegment(text: "内存 ", isWarning: false), TitleSegment(text: percent(memory), isWarning: isWarning(memory))]
        if let network {
            first.append(TitleSegment(text: "\t↓" + shortSpeed(network.downBytesPerSecond), isWarning: false))
            second.append(TitleSegment(text: "\t↑" + shortSpeed(network.upBytesPerSecond), isWarning: false))
        }
        return [first, second]
    }

    // MARK: 网速

    /// 菜单里用："56 KB/s"、"1.2 MB/s"、"1.5 GB/s"；nil → "--"。1 KB = 1024 字节。
    public static func speed(_ bytesPerSecond: Double?) -> String {
        guard let parts = speedParts(bytesPerSecond) else { return "--" }
        return parts.number + " " + parts.unit
    }

    /// 菜单栏用的短写法："56K"、"1.2M"、"2.5G"（省掉 B/s）。数字部分固定占 3 位，不足的在前面补
    /// "数字空格"（U+2007，和数字一样宽）→ 宽度基本恒定，菜单栏不会忽宽忽窄。
    /// 数字最多 3 位（"999"、"1.2"、"128"）：10 以上不带小数。
    public static func shortSpeed(_ bytesPerSecond: Double) -> String {
        guard let parts = speedParts(bytesPerSecond) else { return "--" }
        let padding = String(repeating: "\u{2007}", count: max(0, 3 - parts.number.count))
        return padding + parts.number + String(parts.unit.prefix(1))
    }

    private static func speedParts(_ bytesPerSecond: Double?) -> (number: String, unit: String)? {
        guard let bytesPerSecond, bytesPerSecond.isFinite else { return nil }
        let kilobytes = max(bytesPerSecond, 0) / 1024
        if kilobytes < 999.5 {
            return (String(Int(kilobytes.rounded())), "KB/s")
        }
        let megabytes = kilobytes / 1024
        if megabytes < 9.95 {
            return (String(format: "%.1f", megabytes), "MB/s")
        }
        if megabytes < 999.5 {
            return (String(Int(megabytes.rounded())), "MB/s")
        }
        let gigabytes = megabytes / 1024
        return (gigabytes < 9.95 ? String(format: "%.1f", gigabytes) : String(Int(gigabytes.rounded())), "GB/s")
    }

    private static func roundedPercent(_ value: Double?) -> Int? {
        guard let value, value.isFinite else { return nil }
        return Int(min(max(value, 0), 100).rounded())
    }
}
