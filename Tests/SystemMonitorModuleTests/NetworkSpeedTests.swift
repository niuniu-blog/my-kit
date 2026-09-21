import AppKit
import Foundation
import Testing
@testable import SystemMonitorModule

@Suite struct NetworkSpeedTests {
    private func counters(_ entries: [String: (UInt64, UInt64)]) -> NetworkCounters {
        NetworkCounters(interfaces: entries.mapValues { InterfaceBytes(received: $0.0, sent: $0.1) })
    }

    @Test func speedIsTheByteDeltaDividedBySeconds() throws {
        let earlier = counters(["en0": (1_000, 500)])
        let later = counters(["en0": (21_000, 2_500)])
        let speed = try #require(NetworkSpeed.between(earlier, later, seconds: 2))
        #expect(speed.downBytesPerSecond == 10_000)
        #expect(speed.upBytesPerSecond == 1_000)
    }

    @Test func onlyRealNetworkInterfacesCount() throws {
        // 本机代理会让同一份流量同时出现在回环 lo0 上；VPN 的 utun 流量最终也走 en0。都算进去就重复了。
        let earlier = counters(["en0": (0, 0), "en5": (0, 0), "lo0": (0, 0), "utun4": (0, 0), "awdl0": (0, 0), "bridge0": (0, 0)])
        let later = counters(["en0": (1_000, 100), "en5": (500, 50), "lo0": (9_999, 9_999), "utun4": (8_888, 8_888),
                              "awdl0": (777, 777), "bridge0": (666, 666)])
        let speed = try #require(NetworkSpeed.between(earlier, later, seconds: 1))
        #expect(speed.downBytesPerSecond == 1_500)
        #expect(speed.upBytesPerSecond == 150)
    }

    @Test func interfaceThatJustAppearedIsSkippedForThisRound() throws {
        let earlier = counters(["en0": (100, 100)])
        let later = counters(["en0": (200, 200), "en7": (5_000_000, 5_000_000)])     // 刚插上的网卡：累计值不是这一轮的流量
        let speed = try #require(NetworkSpeed.between(earlier, later, seconds: 1))
        #expect(speed.downBytesPerSecond == 100)
        #expect(speed.upBytesPerSecond == 100)
    }

    @Test func counterThatWentBackwardsIsSkipped() throws {
        let earlier = counters(["en0": (9_000, 9_000), "en1": (100, 100)])
        let later = counters(["en0": (10, 10), "en1": (300, 200)])                  // en0 被重置（断开重连）
        let speed = try #require(NetworkSpeed.between(earlier, later, seconds: 1))
        #expect(speed.downBytesPerSecond == 200)
        #expect(speed.upBytesPerSecond == 100)
    }

    @Test func nonPositiveIntervalGivesNoResult() {
        let sample = counters(["en0": (1, 1)])
        #expect(NetworkSpeed.between(sample, sample, seconds: 0) == nil)
        #expect(NetworkSpeed.between(sample, sample, seconds: -1) == nil)
    }

    @Test func noTrafficIsZeroNotNil() throws {
        let sample = counters(["en0": (5, 5)])
        let speed = try #require(NetworkSpeed.between(sample, sample, seconds: 2))
        #expect(speed.downBytesPerSecond == 0)
        #expect(speed.upBytesPerSecond == 0)
    }
}

@Suite struct NetworkSpeedFormatTests {
    private let kb: Double = 1024
    private let mb: Double = 1_048_576

    @Test func speedsUseKBThenMBThenGB() {
        let small = 56 * kb
        let medium = 1.2 * mb
        let large = 1.5 * 1024 * mb
        #expect(MonitorFormat.speed(nil) == "--")
        #expect(MonitorFormat.speed(0) == "0 KB/s")
        #expect(MonitorFormat.speed(300) == "0 KB/s")             // 不到 1 KB 的零星流量不值得显示
        #expect(MonitorFormat.speed(small) == "56 KB/s")
        #expect(MonitorFormat.speed(medium) == "1.2 MB/s")
        #expect(MonitorFormat.speed(large) == "1.5 GB/s")
    }

    @Test func switchesToMBBeforeShowingFourDigits() {
        let almost = 999.6 * kb
        #expect(MonitorFormat.speed(almost) == "1.0 MB/s")
    }
}

@Suite struct NetworkSettingsTests {
    @Test func showingNetworkSpeedDefaultsToOnAndRoundTrips() {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        #expect(MonitorSettings(defaults: defaults).showNetworkInMenuBar)
        MonitorSettings(defaults: defaults).showNetworkInMenuBar = false
        #expect(!MonitorSettings(defaults: defaults).showNetworkInMenuBar)
    }
}

private final class NetworkHost: HostStatsReading {
    var samples: [NetworkCounters?]
    init(_ samples: [NetworkCounters?]) { self.samples = samples }

    func cpuTicks() -> CPUTicks? { nil }
    func memoryUsage() -> MemoryUsage? { nil }
    func networkCounters() -> NetworkCounters? {
        samples.count > 1 ? samples.removeFirst() : (samples.first ?? nil)
    }
}

private struct NoProcesses: ProcessSampling {
    func sampleAll() -> ProcessSnapshot { ProcessSnapshot(samples: [], timestampNanoseconds: 0) }
}

@MainActor
@Suite struct MonitorEngineNetworkTests {
    private func makeDefaults() -> UserDefaults {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func sample(_ received: UInt64, _ sent: UInt64) -> NetworkCounters {
        NetworkCounters(interfaces: ["en0": InterfaceBytes(received: received, sent: sent)])
    }

    @Test func firstReadingHasNoSpeedSecondOneDoes() async throws {
        var now: TimeInterval = 100
        let host = NetworkHost([sample(0, 0), sample(20_480, 2_048)])
        let engine = MonitorEngine(host: host, processes: NoProcesses(), settings: MonitorSettings(defaults: makeDefaults()),
                                   firstCPUListDelay: 0, usesTimer: false, clock: { now })
        engine.start()
        #expect(engine.lastTotals.network == nil)

        now = 102
        await engine.tick()
        let speed = try #require(engine.lastTotals.network)
        #expect(speed.downBytesPerSecond == 10_240)
        #expect(speed.upBytesPerSecond == 1_024)
    }

    @Test func unreadableCountersGiveNoSpeedAndRecoverLater() async throws {
        var now: TimeInterval = 0
        let host = NetworkHost([sample(0, 0), nil, sample(100, 100), sample(1_124, 612)])
        let engine = MonitorEngine(host: host, processes: NoProcesses(), settings: MonitorSettings(defaults: makeDefaults()),
                                   firstCPUListDelay: 0, usesTimer: false, clock: { now })
        engine.start()
        now = 2
        await engine.tick()                      // 读取失败
        #expect(engine.lastTotals.network == nil)
        now = 4
        await engine.tick()                      // 失败之后的第一份：还没有可比较的上一份
        #expect(engine.lastTotals.network == nil)
        now = 6
        await engine.tick()
        let speed = try #require(engine.lastTotals.network)
        #expect(speed.downBytesPerSecond == 512)
        #expect(speed.upBytesPerSecond == 256)
    }
}

@MainActor
@Suite struct SystemMonitorModuleNetworkTests {
    private func makeDefaults() -> UserDefaults {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func sample(_ received: UInt64, _ sent: UInt64) -> NetworkCounters {
        NetworkCounters(interfaces: ["en0": InterfaceBytes(received: received, sent: sent)])
    }

    @Test func menuBarAndMenuShowTheSpeedOnceTwoReadingsExist() async throws {
        let host = NetworkHost([sample(0, 0), sample(4_096, 1_024)])
        let module = SystemMonitorModule(defaults: makeDefaults(), host: host, processes: NoProcesses(),
                                         firstCPUListDelay: 0, usesTimer: false)
        try module.start()
        #expect(module.currentMenuBarTitle?.string.contains("↓") == false)      // 第一份读数：还算不出速度
        #expect(module.networkHeader.valueLabel.stringValue == "--")

        await module.engine.tick()

        let title = try #require(module.currentMenuBarTitle?.string)
        #expect(title.contains("↓"))
        #expect(title.contains("↑"))
        #expect(module.networkHeader.valueLabel.stringValue.hasPrefix("↓ "))
        #expect(module.networkHeader.detailLabel.stringValue.hasPrefix("↑ "))
    }

    @Test func turningOffTheNetworkSettingRemovesItFromTheMenuBarButNotFromTheMenu() async throws {
        let defaults = makeDefaults()
        let host = NetworkHost([sample(0, 0), sample(4_096, 1_024), sample(8_192, 2_048)])
        let module = SystemMonitorModule(defaults: defaults, host: host, processes: NoProcesses(),
                                         firstCPUListDelay: 0, usesTimer: false)
        try module.start()
        await module.engine.tick()

        MonitorSettings(defaults: defaults).showNetworkInMenuBar = false
        await module.engine.tick()

        let title = try #require(module.currentMenuBarTitle?.string)
        #expect(!title.contains("↓"))
        #expect(module.networkHeader.valueLabel.stringValue.hasPrefix("↓ "))
    }
}

@Suite struct NetworkCountersReaderSmokeTests {
    @Test func realKernelReadReturnsInterfacesIncludingLoopback() throws {
        // 只读内核计数器：不需要任何授权，也不产生网络流量
        let counters = try #require(HostStatsReader().networkCounters())
        #expect(!counters.interfaces.isEmpty)
        #expect(counters.interfaces["lo0"] != nil)
    }
}
