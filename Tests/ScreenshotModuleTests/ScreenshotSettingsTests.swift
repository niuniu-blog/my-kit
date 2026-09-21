import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct ScreenshotSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsToDesktop() {
        let settings = ScreenshotSettings(defaults: makeDefaults())
        #expect(settings.saveFolder == ScreenshotSettings.desktopURL)
        #expect(settings.saveFolder.path.hasSuffix("/Desktop"))
    }

    @Test func storesAndReadsFolder() {
        let defaults = makeDefaults()
        ScreenshotSettings(defaults: defaults).saveFolder = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)

        #expect(ScreenshotSettings(defaults: defaults).saveFolder.path == "/tmp/shots")
        #expect(defaults.string(forKey: ScreenshotSettings.saveFolderKey) == "/tmp/shots")
    }

    @Test func emptyStoredPathFallsBackToDesktop() {
        let defaults = makeDefaults()
        defaults.set("", forKey: ScreenshotSettings.saveFolderKey)
        #expect(ScreenshotSettings(defaults: defaults).saveFolder == ScreenshotSettings.desktopURL)
    }
}
