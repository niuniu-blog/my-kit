import Foundation

/// 一个进程在某一时刻的采样。
public struct ProcessSample: Equatable, Sendable {
    public let pid: Int32
    /// 自进程启动以来累计用掉的 CPU 时间（用户态 + 内核态），纳秒
    public let cpuNanoseconds: UInt64
    /// 内存占用（footprint），与"活动监视器"的"内存"一列同一口径
    public let footprintBytes: UInt64
    /// 可执行文件路径
    public let path: String

    public init(pid: Int32, cpuNanoseconds: UInt64, footprintBytes: UInt64, path: String) {
        self.pid = pid
        self.cpuNanoseconds = cpuNanoseconds
        self.footprintBytes = footprintBytes
        self.path = path
    }
}

/// 排行榜的一行。
public struct TopEntry: Equatable, Sendable, Identifiable {
    public let group: AppGroup
    /// CPU 榜：百分比（按单个核心计，可以超过 100）；内存榜：字节数
    public let value: Double

    public var id: String { group.key }

    public init(group: AppGroup, value: Double) {
        self.group = group
        self.value = value
    }
}

public enum TopProcesses {
    public static let limit = 5
    /// CPU 榜里小于这个百分比的项不显示
    public static let minimumCPUPercent = 0.1

    /// 两份采样 → CPU 榜。与"活动监视器"一致：一个软件占满一个核心 = 100%。
    /// 只统计两次采样里都在、路径没变、CPU 时间没有变小的 pid（否则说明 pid 被系统回收复用了）。
    public static func byCPU(earlier: [ProcessSample], later: [ProcessSample], intervalNanoseconds: UInt64) -> [TopEntry] {
        guard intervalNanoseconds > 0 else { return [] }
        let before = Dictionary(earlier.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var totals: [AppGroup: Double] = [:]
        for sample in later {
            guard let previous = before[sample.pid],
                  previous.path == sample.path,
                  sample.cpuNanoseconds >= previous.cpuNanoseconds,
                  let group = ProcessGrouping.group(forPath: sample.path)
            else { continue }
            let used = Double(sample.cpuNanoseconds - previous.cpuNanoseconds)
            totals[group, default: 0] += used / Double(intervalNanoseconds) * 100
        }
        return ranked(totals.filter { $0.value >= minimumCPUPercent })
    }

    /// 一份采样 → 内存榜。
    public static func byMemory(_ samples: [ProcessSample]) -> [TopEntry] {
        var totals: [AppGroup: Double] = [:]
        for sample in samples {
            guard let group = ProcessGrouping.group(forPath: sample.path) else { continue }
            totals[group, default: 0] += Double(sample.footprintBytes)
        }
        return ranked(totals.filter { $0.value > 0 })
    }

    /// 数值从大到小；数值相同按名字、再按键排序，保证每次刷新顺序稳定。
    private static func ranked(_ totals: [AppGroup: Double]) -> [TopEntry] {
        totals
            .map { TopEntry(group: $0.key, value: $0.value) }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                if lhs.group.fallbackName != rhs.group.fallbackName { return lhs.group.fallbackName < rhs.group.fallbackName }
                return lhs.group.key < rhs.group.key
            }
            .prefix(limit)
            .map { $0 }
    }
}
