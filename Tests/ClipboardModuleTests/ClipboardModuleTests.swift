import AppKit
import Foundation
import Testing
@testable import ClipboardModule

@MainActor
@Suite struct ClipboardModuleTests {
    private func makeModule() throws -> (ClipboardModule, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mykit-test-\(UUID().uuidString)")
        let suite = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let module = try ClipboardModule(databaseURL: dir.appendingPathComponent("clipboard.sqlite"), defaults: defaults)
        return (module, dir)
    }

    @Test func exposesIdentityAndMenuItems() throws {
        let (module, dir) = try makeModule()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(module.id == "clipboard")
        #expect(module.name == "剪切板历史")
        #expect(module.menuItems.map(\.title) == ["打开剪切板", "暂停记录"])
        #expect(module.settingsView != nil)
        #expect(!module.recoveredFromCorruption)
    }

    @Test func pausingUpdatesMenuItemStateAndNotifies() throws {
        let (module, dir) = try makeModule()
        defer { try? FileManager.default.removeItem(at: dir) }
        var notifications: [Bool] = []
        module.onPausedChange = { notifications.append($0) }

        module.isPaused = true
        #expect(module.menuItems[1].state == .on)
        module.isPaused = false
        #expect(module.menuItems[1].state == .off)
        #expect(notifications == [true, false])
    }

    @Test func defaultDatabaseLivesInApplicationSupport() {
        let path = ClipboardModule.defaultDatabaseURL.path
        #expect(path.hasSuffix("Library/Application Support/MyKit/clipboard.sqlite"))
    }
}
