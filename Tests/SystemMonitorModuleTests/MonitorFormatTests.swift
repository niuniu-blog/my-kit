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

    @Test func titleIsFourSegmentsAndOnlyNumbersCanWarn() {
        let segments = MonitorFormat.titleSegments(cpu: 12, memory: 91)

        #expect(segments.map(\.text) == ["CPU ", "12%", "  内存 ", "91%"])
        #expect(segments.map(\.isWarning) == [false, false, false, true])
        #expect(segments.map(\.text).joined() == "CPU 12%  内存 91%")
    }

    @Test func titleBeforeFirstCPUReadingShowsDashes() {
        let text = MonitorFormat.titleSegments(cpu: nil, memory: 63).map(\.text).joined()
        #expect(text == "CPU --  内存 63%")
    }
}
