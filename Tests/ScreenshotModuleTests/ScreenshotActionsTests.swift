import Foundation
import Testing
@testable import ScreenshotModule

@MainActor
@Suite struct ScreenshotActionsTests {
    @Test func savedMessageNamesTheFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mykit-shots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let message = ScreenshotActions.message(for: .saved(folder.appendingPathComponent("a.png")))

        #expect(message == "已保存到 \(folder.lastPathComponent)")
    }

    @Test func fallbackAndFailureMessages() {
        #expect(ScreenshotActions.message(for: .savedToFallback(URL(fileURLWithPath: "/tmp/a.png"))) == "保存失败，已改存到桌面")
        #expect(ScreenshotActions.message(for: .failed) == "保存失败")
    }
}
