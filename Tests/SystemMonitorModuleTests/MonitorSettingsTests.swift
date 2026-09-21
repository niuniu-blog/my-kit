import Foundation
import Testing
@testable import SystemMonitorModule

@Suite struct MonitorSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsAreShowInMenuBarEveryTwoSeconds() {
        let settings = MonitorSettings(defaults: makeDefaults())
        #expect(settings.showInMenuBar)
        #expect(settings.interval == 2)
    }

    @Test func valuesRoundTrip() {
        let defaults = makeDefaults()
        MonitorSettings(defaults: defaults).showInMenuBar = false
        MonitorSettings(defaults: defaults).interval = 5

        #expect(!MonitorSettings(defaults: defaults).showInMenuBar)
        #expect(MonitorSettings(defaults: defaults).interval == 5)
    }

    @Test func unsupportedIntervalFallsBackToTwo() {
        let defaults = makeDefaults()
        defaults.set(3, forKey: MonitorSettings.intervalKey)
        #expect(MonitorSettings(defaults: defaults).interval == 2)
        defaults.set(-1, forKey: MonitorSettings.intervalKey)
        #expect(MonitorSettings(defaults: defaults).interval == 2)
    }

    @Test func changesPostNotificationForThatDefaults() {
        let defaults = makeDefaults()
        var count = 0
        let token = NotificationCenter.default.addObserver(
            forName: MonitorSettings.didChangeNotification, object: defaults, queue: nil
        ) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        MonitorSettings(defaults: defaults).showInMenuBar = false
        MonitorSettings(defaults: defaults).interval = 1
        MonitorSettings(defaults: defaults).notifyChanged()

        #expect(count == 3)
    }
}
