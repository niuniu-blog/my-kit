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

    @Test func pollsQuicklyWhileWaitingForPermissionAndSlowlyOnceTrusted() {
        // 等用户授权时每秒查一次（授权后马上生效）；已经授权后只需偶尔确认没被撤销
        var trusted = false
        let watcher = AccessibilityWatcher(check: { trusted })
        #expect(watcher.currentInterval == 1.0)

        trusted = true
        watcher.poll()
        #expect(watcher.currentInterval == 5.0)

        trusted = false
        watcher.poll()
        #expect(watcher.currentInterval == 1.0)
    }

    @Test func startsSlowWhenAlreadyTrusted() {
        let watcher = AccessibilityWatcher(check: { true })
        #expect(watcher.currentInterval == 5.0)
    }
}
