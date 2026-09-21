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
    public static func titleSegments(cpu: Double?, memory: Double?) -> [TitleSegment] {
        [
            TitleSegment(text: "CPU ", isWarning: false),
            TitleSegment(text: percent(cpu), isWarning: isWarning(cpu)),
            TitleSegment(text: "  内存 ", isWarning: false),
            TitleSegment(text: percent(memory), isWarning: isWarning(memory)),
        ]
    }

    private static func roundedPercent(_ value: Double?) -> Int? {
        guard let value, value.isFinite else { return nil }
        return Int(min(max(value, 0), 100).rounded())
    }
}
