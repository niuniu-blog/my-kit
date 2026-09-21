import Testing
@testable import SystemMonitorModule

@Suite struct MemoryUsageTests {
    private let gigabyte: UInt64 = 1_073_741_824

    @Test func usedIsAppMemoryPlusWiredPlusCompressed() {
        // 页大小 16 KB；internal 500 − purgeable 100 = 400，加 wired 200、compressed 50 → 650 页
        let usage = MemoryUsage.from(
            internalPages: 500, purgeablePages: 100, wiredPages: 200, compressedPages: 50,
            pageSize: 16_384, totalBytes: 16 * gigabyte)

        #expect(usage.usedBytes == 10_649_600)      // 650 × 16384
        #expect(usage.totalBytes == 16 * gigabyte)
    }

    @Test func purgeableLargerThanInternalCountsAsZeroAppMemory() {
        let usage = MemoryUsage.from(
            internalPages: 10, purgeablePages: 30, wiredPages: 5, compressedPages: 5,
            pageSize: 4096, totalBytes: gigabyte)
        #expect(usage.usedBytes == 40_960)          // 只剩 wired + compressed = 10 页
    }

    @Test func percentIsUsedOverTotalClampedToOneHundred() {
        #expect(MemoryUsage(usedBytes: 4 * gigabyte, totalBytes: 16 * gigabyte).percent == 25)
        #expect(MemoryUsage(usedBytes: 20 * gigabyte, totalBytes: 16 * gigabyte).percent == 100)
        #expect(MemoryUsage(usedBytes: 1, totalBytes: 0).percent == 0)
    }
}
