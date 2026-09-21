import Foundation
import Testing
@testable import UninstallerModule

@Suite struct SizeCalculatorTests {
    @Test func directorySizeCoversNestedFiles() throws {
        let temp = try TempDir()
        try temp.makeFile("Big/a.bin", bytes: 200_000)
        try temp.makeFile("Big/nested/deeper/b.bin", bytes: 300_000)

        let size = try #require(SizeCalculator.allocatedSize(of: temp.url.appendingPathComponent("Big")))

        #expect(size >= 500_000)
        #expect(size < 2_000_000)                     // 按块分配会略大于内容，但不会离谱
    }

    @Test func singleFileAndMissingPath() throws {
        let temp = try TempDir()
        let file = try temp.makeFile("one.bin", bytes: 100_000)

        let fileSize = try #require(SizeCalculator.allocatedSize(of: file))
        #expect(fileSize >= 100_000)
        #expect(SizeCalculator.allocatedSize(of: temp.url.appendingPathComponent("missing")) == 0)
    }

    @Test func symlinksAreNotFollowed() throws {
        let temp = try TempDir()
        try temp.makeFile("Target/huge.bin", bytes: 900_000)
        try temp.makeDirectory("Holder")
        try FileManager.default.createSymbolicLink(
            at: temp.url.appendingPathComponent("Holder/link"), withDestinationURL: temp.url.appendingPathComponent("Target"))

        let size = try #require(SizeCalculator.allocatedSize(of: temp.url.appendingPathComponent("Holder")))

        #expect(size < 100_000)
    }

    @Test func cancellationReturnsNil() throws {
        let temp = try TempDir()
        for index in 0..<300 {
            try temp.makeFile("Many/file-\(index).bin", bytes: 8)
        }
        #expect(SizeCalculator.allocatedSize(of: temp.url.appendingPathComponent("Many"), isCancelled: { true }) == nil)
    }

    @Test func formatting() {
        let kilobyte: UInt64 = 1024
        let megabyte: UInt64 = 1_048_576
        let gigabyte: UInt64 = 1_073_741_824
        #expect(SizeCalculator.format(0) == "0 KB")
        #expect(SizeCalculator.format(100) == "1 KB")
        #expect(SizeCalculator.format(4 * kilobyte) == "4 KB")
        #expect(SizeCalculator.format(850 * megabyte) == "850 MB")
        #expect(SizeCalculator.format(gigabyte) == "1.0 GB")
        #expect(SizeCalculator.format(gigabyte * 23 / 10) == "2.3 GB")
    }
}

@Suite struct AppListingTests {
    private func app(_ title: String, id: String, size: UInt64?) -> InstalledApp {
        InstalledApp(
            identity: AppIdentity(url: URL(fileURLWithPath: "/Applications/\(title).app"), bundleID: id, names: [title]),
            title: title, sizeBytes: size)
    }

    @Test func searchMatchesTitleNameAndBundleIdentifier() {
        let apps = [app("微信", id: "com.tencent.xinWeChat", size: nil), app("Google Chrome", id: "com.google.Chrome", size: nil)]

        #expect(AppListing.filter(apps, query: "").count == 2)
        #expect(AppListing.filter(apps, query: "  ").count == 2)
        #expect(AppListing.filter(apps, query: "微").map(\.title) == ["微信"])
        #expect(AppListing.filter(apps, query: "chrome").map(\.title) == ["Google Chrome"])
        #expect(AppListing.filter(apps, query: "TENCENT").map(\.title) == ["微信"])
        #expect(AppListing.filter(apps, query: "nothing").isEmpty)
    }

    @Test func sortByNameUsesNaturalOrder() {
        let apps = [app("Tool 10", id: "a.b.c10", size: nil), app("tool 2", id: "a.b.c2", size: nil), app("Alpha", id: "a.b.alpha", size: nil)]
        #expect(AppListing.sorted(apps, by: .name).map(\.title) == ["Alpha", "tool 2", "Tool 10"])
    }

    @Test func sortBySizePutsBiggestFirstAndUnknownLast() {
        let apps = [
            app("Small", id: "a.b.small", size: 10), app("Pending", id: "a.b.pending", size: nil),
            app("Big", id: "a.b.big", size: 900), app("Also Pending", id: "a.b.also", size: nil),
        ]
        #expect(AppListing.sorted(apps, by: .size).map(\.title) == ["Big", "Small", "Also Pending", "Pending"])
    }

    @Test func sortOrderTitlesAreChinese() {
        #expect(AppListing.SortOrder.allCases.map(\.title) == ["名称", "大小"])
    }
}
