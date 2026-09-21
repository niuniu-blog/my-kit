import Foundation
import Testing
@testable import ClipboardModule

@Suite struct ClipboardSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsToSevenDays() {
        #expect(ClipboardSettings(defaults: makeDefaults()).retentionDays == 7)
    }

    @Test func storesAndReadsValue() {
        let defaults = makeDefaults()
        ClipboardSettings(defaults: defaults).retentionDays = 30
        #expect(ClipboardSettings(defaults: defaults).retentionDays == 30)
        #expect(defaults.integer(forKey: ClipboardSettings.retentionDaysKey) == 30)
    }

    @Test func clampsOutOfRangeValues() {
        let defaults = makeDefaults()
        defaults.set(500, forKey: ClipboardSettings.retentionDaysKey)
        #expect(ClipboardSettings(defaults: defaults).retentionDays == 90)
        defaults.set(-3, forKey: ClipboardSettings.retentionDaysKey)
        #expect(ClipboardSettings(defaults: defaults).retentionDays == 1)
    }
}
