import Testing
@testable import SystemMonitorModule

@Suite struct MonitorFormatTests {
    private let gigabyte: UInt64 = 1_073_741_824
    private let megabyte: UInt64 = 1_048_576

    @Test func totalPercentIsRoundedAndClamped() {
        #expect(MonitorFormat.percent(12.4) == "12%")
        #expect(MonitorFormat.percent(12.5) == "13%")
        #expect(MonitorFormat.percent(0) == "0%")
        #expect(MonitorFormat.percent(130) == "100%")
        #expect(MonitorFormat.percent(-3) == "0%")
    }

    @Test func missingValueShowsDashes() {
        #expect(MonitorFormat.percent(nil) == "--")
        #expect(MonitorFormat.percent(Double.nan) == "--")
    }

    @Test func perAppPercentKeepsOneDecimalAndMayExceedOneHundred() {
        #expect(MonitorFormat.percentOneDecimal(28.44) == "28.4%")
        #expect(MonitorFormat.percentOneDecimal(250) == "250.0%")
        #expect(MonitorFormat.percentOneDecimal(0.1) == "0.1%")
    }

    @Test func bytesUseGigabytesFromOneGigabyteUp() {
        let threePointTwo = 3 * gigabyte + 205 * megabyte
        #expect(MonitorFormat.bytes(threePointTwo) == "3.2 GB")
        #expect(MonitorFormat.bytes(gigabyte) == "1.0 GB")
        #expect(MonitorFormat.bytes(850 * megabyte) == "850 MB")
        #expect(MonitorFormat.bytes(0) == "0 MB")
    }

    @Test func memorySummaryShowsUsedOverTotal() {
        let used = 10 * gigabyte + 103 * megabyte
        #expect(MonitorFormat.memorySummary(usedBytes: used, totalBytes: 16 * gigabyte) == "10.1 / 16 GB")
        let oddTotal = 18 * gigabyte + 512 * megabyte
        #expect(MonitorFormat.memorySummary(usedBytes: gigabyte, totalBytes: oddTotal) == "1.0 / 18.5 GB")
    }

    @Test func warningStartsAtEightyFiveAsDisplayed() {
        #expect(!MonitorFormat.isWarning(84.4))
        #expect(MonitorFormat.isWarning(84.5))       // 显示为 85%，所以也标红
        #expect(MonitorFormat.isWarning(85))
        #expect(MonitorFormat.isWarning(100))
        #expect(!MonitorFormat.isWarning(nil))
    }

    @Test func titleIsTwoLinesAndOnlyNumbersCanWarn() {
        let lines = MonitorFormat.titleLines(cpu: 12, memory: 91, network: nil)

        #expect(lines.count == 2)
        #expect(lines[0].map(\.text) == ["CPU ", "12%"])
        #expect(lines[1].map(\.text) == ["内存 ", "91%"])
        #expect(lines[0].map(\.isWarning) == [false, false])
        #expect(lines[1].map(\.isWarning) == [false, true])
    }

    @Test func titleBeforeFirstCPUReadingShowsDashes() {
        let lines = MonitorFormat.titleLines(cpu: nil, memory: 63, network: nil)
        #expect(lines[0].map(\.text).joined() == "CPU --")
        #expect(lines[1].map(\.text).joined() == "内存 63%")
    }

    @Test func networkSpeedsGoInASecondColumnDownloadOnTopUploadBelow() {
        let megabyte: Double = 1_048_576
        let speed = NetworkSpeed(downBytesPerSecond: 1.2 * megabyte, upBytesPerSecond: 56 * 1024)
        let lines = MonitorFormat.titleLines(cpu: 12, memory: 63, network: speed)
        let figureSpace = "\u{2007}"

        // "\t" 是列分隔：第二列在两行里左对齐
        #expect(lines[0].map(\.text).joined() == "CPU 12%\t↓1.2M")
        #expect(lines[1].map(\.text).joined() == "内存 63%\t↑" + figureSpace + "56K")
        #expect(lines.joined().filter(\.isWarning).isEmpty)
    }

    @Test func shortSpeedDropsTheBPerSecondSuffixAndKeepsAConstantWidth() {
        let figureSpace = "\u{2007}"
        let megabyte: Double = 1_048_576
        let big = 128 * megabyte
        let huge = 2.5 * 1024 * megabyte
        let twelve = 12.3 * megabyte
        #expect(MonitorFormat.shortSpeed(0) == figureSpace + figureSpace + "0K")
        #expect(MonitorFormat.shortSpeed(57_344) == figureSpace + "56K")
        #expect(MonitorFormat.shortSpeed(twelve) == figureSpace + "12M")      // 10 MB 以上不要小数：数字最多 3 位
        #expect(MonitorFormat.shortSpeed(big) == "128M")
        #expect(MonitorFormat.shortSpeed(huge) == "2.5G")
    }
}
