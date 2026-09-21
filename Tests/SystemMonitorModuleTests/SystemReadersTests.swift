import Darwin
import Foundation
import Testing
@testable import SystemMonitorModule

/// 冒烟测试：只确认真的能从内核读到东西、数值在合理范围内，不依赖当前的系统负载。
@Suite struct SystemReadersTests {
    @Test func cpuTicksCoverEveryCore() throws {
        let ticks = try #require(HostStatsReader().cpuTicks())
        #expect(ticks.cores.count == ProcessInfo.processInfo.processorCount)
    }

    @Test func twoCPUReadingsNeverGoBackwardsMoreThanAWrap() throws {
        let reader = HostStatsReader()
        let first = try #require(reader.cpuTicks())
        let second = try #require(reader.cpuTicks())
        #expect(first.cores.count == second.cores.count)
        if let load = CPULoad.between(first, second) {        // 两次读得太近时可能是 nil，也算正常
            #expect(load.total >= 0)
            #expect(load.total <= 100)
        }
    }

    @Test func memoryUsageIsWithinPhysicalMemory() throws {
        let usage = try #require(HostStatsReader().memoryUsage())
        #expect(usage.totalBytes == ProcessInfo.processInfo.physicalMemory)
        #expect(usage.usedBytes > 0)
        #expect(usage.usedBytes <= usage.totalBytes)
    }

    @Test func processSnapshotContainsThisTestProcess() throws {
        let snapshot = ProcessSampler().sampleAll()
        let me = try #require(snapshot.samples.first { $0.pid == getpid() })
        #expect(!me.path.isEmpty)
        #expect(me.footprintBytes > 0)
        #expect(me.cpuNanoseconds > 0)
        #expect(snapshot.timestampNanoseconds > 0)
    }

    @Test func snapshotsAreTakenInTimeOrder() {
        let sampler = ProcessSampler()
        let first = sampler.sampleAll()
        let second = sampler.sampleAll()
        #expect(second.timestampNanoseconds >= first.timestampNanoseconds)
    }
}
