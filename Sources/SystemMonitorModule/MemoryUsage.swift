import Foundation

public struct MemoryUsage: Equatable, Sendable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64

    public init(usedBytes: UInt64, totalBytes: UInt64) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }

    /// 0…100
    public var percent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes) * 100, 0), 100)
    }

    /// 与"活动监视器"的"已使用内存"同一口径：App 内存（internal − purgeable）+ 联动内存 + 被压缩的内存。
    public static func from(
        internalPages: UInt64,
        purgeablePages: UInt64,
        wiredPages: UInt64,
        compressedPages: UInt64,
        pageSize: UInt64,
        totalBytes: UInt64
    ) -> MemoryUsage {
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let used = (appPages + wiredPages + compressedPages) * pageSize
        return MemoryUsage(usedBytes: used, totalBytes: totalBytes)
    }
}
