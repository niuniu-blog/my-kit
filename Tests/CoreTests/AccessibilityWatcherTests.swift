import Testing
@testable import Core

@MainActor
@Suite struct AccessibilityWatcherTests {
    @Test func reportsInitialStateWithoutFiringCallback() {
        var changes: [Bool] = []
        let watcher = AccessibilityWatcher(check: { true })
        watcher.onChange = { changes.append($0) }

        watcher.poll()

        #expect(watcher.isTrusted)
        #expect(changes.isEmpty)
    }

    @Test func firesOnlyWhenValueChanges() {
        var trusted = false
        var changes: [Bool] = []
        let watcher = AccessibilityWatcher(check: { trusted })
        watcher.onChange = { changes.append($0) }

        watcher.poll()
        trusted = true
        watcher.poll()
        watcher.poll()
        trusted = false
        watcher.poll()

        #expect(changes == [true, false])
        #expect(!watcher.isTrusted)
    }
}
