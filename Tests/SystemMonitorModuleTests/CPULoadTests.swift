import Testing
@testable import SystemMonitorModule

@Suite struct CPULoadTests {
    private func ticks(_ cores: [(UInt32, UInt32, UInt32, UInt32)]) -> CPUTicks {
        CPUTicks(cores: cores.map { CoreTicks(user: $0.0, system: $0.1, idle: $0.2, nice: $0.3) })
    }

    @Test func computesUserAndSystemShareAcrossAllCores() throws {
        let earlier = ticks([(100, 50, 850, 0), (200, 100, 700, 0)])
        let later = ticks([(130, 60, 910, 0), (210, 110, 780, 0)])     // Δ：用户 40，系统 20，空闲 140 → 共 200

        let load = try #require(CPULoad.between(earlier, later))

        #expect(load.user == 20)
        #expect(load.system == 10)
        #expect(load.total == 30)
    }

    @Test func niceCountsAsUser() throws {
        let load = try #require(CPULoad.between(ticks([(0, 0, 0, 0)]), ticks([(10, 0, 80, 10)])))
        #expect(load.user == 20)
        #expect(load.system == 0)
    }

    @Test func survivesThirtyTwoBitCounterWraparound() throws {
        let nearMax = UInt32.max - 9
        let earlier = ticks([(nearMax, 0, nearMax, 0)])
        let later = ticks([(40, 0, 40, 0)])                             // 两个计数器都绕回去了，各走了 50

        let load = try #require(CPULoad.between(earlier, later))

        #expect(load.user == 50)
        #expect(load.system == 0)
    }

    @Test func returnsNilWhenCoreCountChanges() {
        #expect(CPULoad.between(ticks([(1, 1, 1, 0)]), ticks([(2, 2, 2, 0), (1, 1, 1, 0)])) == nil)
    }

    @Test func returnsNilWhenNothingTickedOrNoCores() {
        let same = ticks([(5, 5, 5, 5)])
        #expect(CPULoad.between(same, same) == nil)
        #expect(CPULoad.between(ticks([]), ticks([])) == nil)
    }

    @Test func fullyBusyIsOneHundredPercent() throws {
        let load = try #require(CPULoad.between(ticks([(0, 0, 0, 0)]), ticks([(70, 30, 0, 0)])))
        #expect(load.total == 100)
    }
}
