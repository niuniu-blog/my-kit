import Foundation
import Testing
@testable import SystemMonitorModule

private final class FakeHost: HostStatsReading {
    var ticksQueue: [CPUTicks?]
    var memory: MemoryUsage?
    private(set) var cpuReads = 0

    init(ticks: [CPUTicks?], memory: MemoryUsage?) {
        self.ticksQueue = ticks
        self.memory = memory
    }

    func cpuTicks() -> CPUTicks? {
        cpuReads += 1
        return ticksQueue.isEmpty ? nil : ticksQueue.removeFirst()
    }

    func memoryUsage() -> MemoryUsage? { memory }
}

/// 会在后台线程被调用，所以用锁保护。
private final class FakeSampler: ProcessSampling, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [ProcessSnapshot]
    private var calls = 0

    init(_ snapshots: [ProcessSnapshot]) {
        self.queue = snapshots
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return calls
    }

    func sampleAll() -> ProcessSnapshot {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        if queue.count > 1 { return queue.removeFirst() }
        return queue.first ?? ProcessSnapshot(samples: [], timestampNanoseconds: UInt64(calls))
    }
}

@MainActor
@Suite struct MonitorEngineTests {
    private let gigabyte: UInt64 = 1_073_741_824
    private let second: UInt64 = 1_000_000_000

    private func makeDefaults() -> UserDefaults {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func ticks(user: UInt32, idle: UInt32) -> CPUTicks {
        CPUTicks(cores: [CoreTicks(user: user, system: 0, idle: idle, nice: 0)])
    }

    private func snapshot(atSecond time: UInt64, chromeCPUMilliseconds: UInt64) -> ProcessSnapshot {
        ProcessSnapshot(
            samples: [
                ProcessSample(pid: 1, cpuNanoseconds: chromeCPUMilliseconds * 1_000_000, footprintBytes: 2 * gigabyte,
                              path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
                ProcessSample(pid: 2, cpuNanoseconds: 0, footprintBytes: gigabyte, path: "/usr/local/bin/node"),
            ],
            timestampNanoseconds: time * second)
    }

    private func makeEngine(host: FakeHost, sampler: FakeSampler, defaults: UserDefaults) -> MonitorEngine {
        MonitorEngine(host: host, processes: sampler, settings: MonitorSettings(defaults: defaults),
                      firstCPUListDelay: 0, usesTimer: false)
    }

    @Test func firstReadingHasMemoryButNoCPUAndSecondHasBoth() async {
        let memory = MemoryUsage(usedBytes: 8 * gigabyte, totalBytes: 16 * gigabyte)
        let host = FakeHost(ticks: [ticks(user: 0, idle: 0), ticks(user: 25, idle: 75)], memory: memory)
        let engine = makeEngine(host: host, sampler: FakeSampler([]), defaults: makeDefaults())
        var received: [MonitorEngine.Totals] = []
        engine.onTotals = { received.append($0) }

        engine.start()
        await engine.tick()

        #expect(received.count == 2)
        #expect(received[0] == MonitorEngine.Totals(cpu: nil, memory: memory))
        #expect(received[1].cpu?.total == 25)
        #expect(engine.lastTotals == received[1])
    }

    @Test func keepsLastCPUValueWhenTwoReadingsAreIdentical() async {
        let same = ticks(user: 25, idle: 75)
        let host = FakeHost(ticks: [ticks(user: 0, idle: 0), same, same], memory: nil)
        let engine = makeEngine(host: host, sampler: FakeSampler([]), defaults: makeDefaults())

        engine.start()
        await engine.tick()
        await engine.tick()

        #expect(engine.lastTotals.cpu?.total == 25)
    }

    @Test func kernelFailureShowsNoValue() async {
        let host = FakeHost(ticks: [ticks(user: 0, idle: 0), ticks(user: 50, idle: 50), nil], memory: nil)
        let engine = makeEngine(host: host, sampler: FakeSampler([]), defaults: makeDefaults())

        engine.start()
        await engine.tick()
        #expect(engine.lastTotals.cpu != nil)
        await engine.tick()

        #expect(engine.lastTotals == MonitorEngine.Totals(cpu: nil, memory: nil))
    }

    @Test func processesAreSampledOnlyWhileTheMenuIsOpen() async {
        let sampler = FakeSampler([snapshot(atSecond: 1, chromeCPUMilliseconds: 0)])
        let engine = makeEngine(host: FakeHost(ticks: [], memory: nil), sampler: sampler, defaults: makeDefaults())
        engine.start()

        await engine.tick()
        #expect(sampler.callCount == 0)

        engine.setMenuOpen(true)
        await engine.tick()
        #expect(sampler.callCount == 1)

        engine.setMenuOpen(false)
        await engine.tick()
        #expect(sampler.callCount == 1)
    }

    @Test func openingTheMenuGivesMemoryListAtOnceAndCPUListOnTheSecondSample() async {
        let sampler = FakeSampler([
            snapshot(atSecond: 10, chromeCPUMilliseconds: 1000),
            snapshot(atSecond: 11, chromeCPUMilliseconds: 1500),
        ])
        let engine = makeEngine(host: FakeHost(ticks: [], memory: nil), sampler: sampler, defaults: makeDefaults())
        var lists: [MonitorEngine.TopLists] = []
        engine.onTopLists = { lists.append($0) }
        engine.start()

        await engine.menuDidOpen()

        #expect(lists.count == 2)
        #expect(lists[0].cpu == nil)                                          // 正在统计…
        #expect(lists[0].memory.map(\.group.fallbackName) == ["Google Chrome", "node"])
        #expect(lists[1].cpu?.map(\.group.fallbackName) == ["Google Chrome"]) // node 是 0%，被过滤
        #expect(lists[1].cpu?.first?.value == 50)                             // 500 毫秒 / 1 秒
    }

    @Test func reopeningTheMenuStartsCountingFromScratch() async {
        let sampler = FakeSampler([
            snapshot(atSecond: 10, chromeCPUMilliseconds: 1000),
            snapshot(atSecond: 11, chromeCPUMilliseconds: 1500),
            snapshot(atSecond: 99, chromeCPUMilliseconds: 9000),
        ])
        let engine = makeEngine(host: FakeHost(ticks: [], memory: nil), sampler: sampler, defaults: makeDefaults())
        var lists: [MonitorEngine.TopLists] = []
        engine.onTopLists = { lists.append($0) }
        engine.start()
        await engine.menuDidOpen()
        engine.setMenuOpen(false)
        lists.removeAll()

        engine.setMenuOpen(true)
        await engine.tick()

        #expect(lists.count == 1)
        #expect(lists[0].cpu == nil)          // 不会拿关闭前的旧样本来算
    }

    @Test func nothingRunsWhenMenuBarDisplayIsOffAndMenuIsClosed() async {
        let defaults = makeDefaults()
        MonitorSettings(defaults: defaults).showInMenuBar = false
        let host = FakeHost(ticks: [ticks(user: 0, idle: 0)], memory: nil)
        let engine = makeEngine(host: host, sampler: FakeSampler([]), defaults: defaults)

        engine.start()
        await engine.tick()

        #expect(!engine.wantsTimer)
        #expect(host.cpuReads == 0)
    }

    @Test func openingTheMenuRunsTheTimerEvenWhenMenuBarDisplayIsOff() async {
        let defaults = makeDefaults()
        MonitorSettings(defaults: defaults).showInMenuBar = false
        let host = FakeHost(ticks: [ticks(user: 0, idle: 0), ticks(user: 10, idle: 90)], memory: nil)
        let engine = makeEngine(host: host, sampler: FakeSampler([]), defaults: defaults)
        engine.start()

        await engine.menuDidOpen()

        #expect(engine.wantsTimer)
        #expect(engine.lastTotals.cpu?.total == 10)      // 打开后的两次采样就能给出 CPU

        engine.setMenuOpen(false)
        #expect(!engine.wantsTimer)
    }

    @Test func applySettingsFollowsTheShowInMenuBarSwitch() {
        let defaults = makeDefaults()
        let engine = makeEngine(host: FakeHost(ticks: [], memory: nil), sampler: FakeSampler([]), defaults: defaults)
        engine.start()
        #expect(engine.wantsTimer)

        MonitorSettings(defaults: defaults).showInMenuBar = false
        engine.applySettings()
        #expect(!engine.wantsTimer)

        MonitorSettings(defaults: defaults).showInMenuBar = true
        engine.applySettings()
        #expect(engine.wantsTimer)
    }

    @Test func staleCPUBaselineIsDroppedWhileStopped() async {
        let defaults = makeDefaults()
        let host = FakeHost(ticks: [ticks(user: 0, idle: 0), ticks(user: 50, idle: 50), ticks(user: 950, idle: 1050)], memory: nil)
        let engine = makeEngine(host: host, sampler: FakeSampler([]), defaults: defaults)
        engine.start()
        await engine.tick()
        #expect(engine.lastTotals.cpu?.total == 50)

        MonitorSettings(defaults: defaults).showInMenuBar = false
        engine.applySettings()
        MonitorSettings(defaults: defaults).showInMenuBar = true
        engine.applySettings()
        await engine.tick()

        #expect(engine.lastTotals.cpu == nil)     // 停了一段时间：旧快照作废，要重新攒两份
    }

    @Test func refreshTotalsReadsImmediatelyButOnlyWhenSamplingIsWanted() {
        let defaults = makeDefaults()
        let host = FakeHost(ticks: [ticks(user: 0, idle: 0), ticks(user: 1, idle: 1)], memory: nil)
        let engine = makeEngine(host: host, sampler: FakeSampler([]), defaults: defaults)

        engine.refreshTotals()
        #expect(host.cpuReads == 0)          // 还没 start

        engine.start()
        engine.refreshTotals()
        #expect(host.cpuReads == 2)          // start 读一次 + 这一次

        MonitorSettings(defaults: defaults).showInMenuBar = false
        engine.applySettings()
        engine.refreshTotals()
        #expect(host.cpuReads == 2)          // 不显示、菜单也没开：不读
    }

    @Test func stopEndsEverything() async {
        let sampler = FakeSampler([snapshot(atSecond: 1, chromeCPUMilliseconds: 0)])
        let engine = makeEngine(host: FakeHost(ticks: [], memory: nil), sampler: sampler, defaults: makeDefaults())
        engine.start()
        engine.setMenuOpen(true)

        engine.stop()
        await engine.tick()

        #expect(!engine.wantsTimer)
        #expect(!engine.isMenuOpen)
        #expect(sampler.callCount == 0)
    }
}
