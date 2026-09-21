import Testing
@testable import SystemMonitorModule

@Suite struct TopProcessesTests {
    private let second: UInt64 = 1_000_000_000
    private let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    private let chromeHelper = "/Applications/Google Chrome.app/Contents/Frameworks/F.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
    private let wechat = "/Applications/WeChat.app/Contents/MacOS/WeChat"

    private func sample(_ pid: Int32, cpuMilliseconds: UInt64, megabytes: UInt64 = 10, path: String) -> ProcessSample {
        ProcessSample(pid: pid, cpuNanoseconds: cpuMilliseconds * 1_000_000, footprintBytes: megabytes * 1_048_576, path: path)
    }

    @Test func cpuIsSummedPerAppAndExpressedPerCore() {
        let earlier = [sample(1, cpuMilliseconds: 1000, path: chrome), sample(2, cpuMilliseconds: 500, path: chromeHelper), sample(3, cpuMilliseconds: 0, path: wechat)]
        let later = [sample(1, cpuMilliseconds: 1300, path: chrome), sample(2, cpuMilliseconds: 1400, path: chromeHelper), sample(3, cpuMilliseconds: 100, path: wechat)]

        let top = TopProcesses.byCPU(earlier: earlier, later: later, intervalNanoseconds: 2 * second)

        #expect(top.map(\.group.fallbackName) == ["Google Chrome", "WeChat"])
        #expect(top[0].value == 60)      // (300 + 900) 毫秒 / 2 秒
        #expect(top[1].value == 5)
    }

    @Test func aBusyMultiThreadedAppCanExceedOneHundredPercent() {
        let top = TopProcesses.byCPU(
            earlier: [sample(1, cpuMilliseconds: 0, path: chrome)],
            later: [sample(1, cpuMilliseconds: 2500, path: chrome)],
            intervalNanoseconds: second)
        #expect(top.first?.value == 250)
    }

    @Test func ignoresNewProcessesAndReusedPids() {
        let earlier = [sample(1, cpuMilliseconds: 5000, path: chrome), sample(2, cpuMilliseconds: 100, path: wechat)]
        let later = [
            sample(1, cpuMilliseconds: 200, path: chrome),          // CPU 时间变小：pid 被复用了
            sample(2, cpuMilliseconds: 900, path: "/usr/bin/yes"),  // 同一个 pid 换了程序
            sample(9, cpuMilliseconds: 800, path: wechat),          // 第一次采样时还不存在
        ]
        #expect(TopProcesses.byCPU(earlier: earlier, later: later, intervalNanoseconds: second).isEmpty)
    }

    @Test func dropsEntriesBelowOneTenthOfAPercentAndKeepsTopFive() {
        var earlier: [ProcessSample] = []
        var later: [ProcessSample] = []
        for index in 1...7 {
            let path = "/opt/tools/tool\(index)"
            earlier.append(sample(Int32(index), cpuMilliseconds: 0, path: path))
            later.append(sample(Int32(index), cpuMilliseconds: UInt64(index) * 10, path: path))
        }
        earlier.append(sample(100, cpuMilliseconds: 0, path: "/opt/tools/idle"))
        later.append(sample(100, cpuMilliseconds: 0, path: "/opt/tools/idle"))

        let top = TopProcesses.byCPU(earlier: earlier, later: later, intervalNanoseconds: second)

        #expect(top.map(\.group.fallbackName) == ["tool7", "tool6", "tool5", "tool4", "tool3"])
    }

    @Test func zeroIntervalGivesNoCPURanking() {
        let samples = [sample(1, cpuMilliseconds: 10, path: chrome)]
        #expect(TopProcesses.byCPU(earlier: samples, later: samples, intervalNanoseconds: 0).isEmpty)
    }

    @Test func memoryIsSummedPerAppLargestFirst() {
        let samples = [
            sample(1, cpuMilliseconds: 0, megabytes: 300, path: chrome),
            sample(2, cpuMilliseconds: 0, megabytes: 500, path: chromeHelper),
            sample(3, cpuMilliseconds: 0, megabytes: 900, path: wechat),
            sample(4, cpuMilliseconds: 0, megabytes: 50, path: ""),          // 读不到路径的进程不参与
        ]

        let top = TopProcesses.byMemory(samples)

        #expect(top.map(\.group.fallbackName) == ["WeChat", "Google Chrome"])
        #expect(top[0].value == 943_718_400)     // 900 MB
        #expect(top[1].value == 838_860_800)     // 800 MB
    }

    @Test func equalValuesAreOrderedByNameSoTheListDoesNotFlicker() {
        let samples = [
            sample(1, cpuMilliseconds: 0, megabytes: 100, path: "/opt/zeta"),
            sample(2, cpuMilliseconds: 0, megabytes: 100, path: "/opt/alpha"),
            sample(3, cpuMilliseconds: 0, megabytes: 100, path: "/opt/mid"),
        ]
        #expect(TopProcesses.byMemory(samples).map(\.group.fallbackName) == ["alpha", "mid", "zeta"])
    }

    @Test func memoryRankingKeepsOnlyTopFive() {
        let samples = (1...8).map { sample(Int32($0), cpuMilliseconds: 0, megabytes: UInt64($0) * 10, path: "/opt/p\($0)") }
        #expect(TopProcesses.byMemory(samples).map(\.group.fallbackName) == ["p8", "p7", "p6", "p5", "p4"])
    }
}
