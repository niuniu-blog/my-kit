import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct ScreenshotFileNamerTests {
    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-09-21 14:32:05 UTC
    private let date = Date(timeIntervalSince1970: 1_790_001_125)

    @Test func baseNameUsesDateAndTimeWithDots() {
        #expect(ScreenshotFileNamer.baseName(for: date, timeZone: utc) == "MyKit 2026-09-21 14.32.05")
    }

    @Test func fileNameAddsPNGExtension() {
        let name = ScreenshotFileNamer.fileName(for: date, timeZone: utc) { _ in false }
        #expect(name == "MyKit 2026-09-21 14.32.05.png")
    }

    @Test func appendsCounterWhenNameIsTaken() {
        let taken: Set<String> = ["MyKit 2026-09-21 14.32.05.png", "MyKit 2026-09-21 14.32.05 (2).png"]
        let name = ScreenshotFileNamer.fileName(for: date, timeZone: utc) { taken.contains($0) }
        #expect(name == "MyKit 2026-09-21 14.32.05 (3).png")
    }
}
