import Foundation

/// 一个核心自开机以来的累计 tick。内核给的是 32 位无符号数，跑久了会回绕。
public struct CoreTicks: Equatable, Sendable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// 某一时刻所有核心的 tick 快照。
public struct CPUTicks: Equatable, Sendable {
    public var cores: [CoreTicks]

    public init(cores: [CoreTicks]) {
        self.cores = cores
    }
}

/// 两份快照之间的 CPU 占用（占全部核心的百分比，0…100）。
public struct CPULoad: Equatable, Sendable {
    /// 用户态（含 nice）
    public let user: Double
    /// 内核态
    public let system: Double

    public var total: Double { user + system }

    public init(user: Double, system: Double) {
        self.user = user
        self.system = system
    }

    /// 核心数对不上、或两次采样之间没有任何 tick（采样太近）时返回 nil。
    public static func between(_ earlier: CPUTicks, _ later: CPUTicks) -> CPULoad? {
        guard !later.cores.isEmpty, earlier.cores.count == later.cores.count else { return nil }
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        for (before, after) in zip(earlier.cores, later.cores) {
            // &- 是回绕减法：计数器从 UInt32.max 绕回 0 之后差值依然正确
            user += UInt64(after.user &- before.user) + UInt64(after.nice &- before.nice)
            system += UInt64(after.system &- before.system)
            idle += UInt64(after.idle &- before.idle)
        }
        let total = user + system + idle
        guard total > 0 else { return nil }
        return CPULoad(
            user: Double(user) / Double(total) * 100,
            system: Double(system) / Double(total) * 100
        )
    }
}
