import Foundation
import Testing
@testable import ClipboardModule

private final class FakePasteboard: PasteboardReading {
    var changeCount = 0
    var types: [String] = []
    var text: String?

    func currentTypeIdentifiers() -> [String] { types }
    func currentString() -> String? { text }

    func copy(_ string: String, extraTypes: [String] = []) {
        text = string
        types = ["public.utf8-plain-text"] + extraTypes
        changeCount += 1
    }
}

@MainActor
@Suite struct ClipboardMonitorTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeMonitor(
        _ pasteboard: FakePasteboard,
        _ store: ClipboardStore,
        now: @escaping () -> Date
    ) -> ClipboardMonitor {
        ClipboardMonitor(
            pasteboard: pasteboard,
            store: store,
            frontmostApp: { (bundleID: "com.apple.Safari", name: "Safari") },
            now: now
        )
    }

    @Test func recordsNewCopyWithSourceApp() async throws {
        let pasteboard = FakePasteboard()
        let store = try ClipboardStore(location: .inMemory)
        let monitor = makeMonitor(pasteboard, store, now: { self.t0 })

        pasteboard.copy("hello")
        await monitor.poll()

        let items = try await store.search(query: "", limit: 10, offset: 0)
        #expect(items.map(\.text) == ["hello"])
        #expect(items.first?.appName == "Safari")
        #expect(items.first?.appBundleID == "com.apple.Safari")
        #expect(items.first?.lastUsedAt == t0)
    }

    @Test func doesNothingWhenChangeCountUnchanged() async throws {
        let pasteboard = FakePasteboard()
        let store = try ClipboardStore(location: .inMemory)
        let monitor = makeMonitor(pasteboard, store, now: { self.t0 })

        pasteboard.copy("once")
        await monitor.poll()
        pasteboard.text = "changed without bumping changeCount"
        await monitor.poll()

        let items = try await store.search(query: "", limit: 10, offset: 0)
        #expect(items.map(\.text) == ["once"])
    }

    @Test func ignoresContentAlreadyOnPasteboardAtCreation() async throws {
        let pasteboard = FakePasteboard()
        pasteboard.copy("copied before MyKit launched")
        let store = try ClipboardStore(location: .inMemory)
        let monitor = makeMonitor(pasteboard, store, now: { self.t0 })

        await monitor.poll()

        let count = try await store.count()
        #expect(count == 0)
    }

    @Test func pausedMonitorSkipsContentEvenAfterResuming() async throws {
        let pasteboard = FakePasteboard()
        let store = try ClipboardStore(location: .inMemory)
        let monitor = makeMonitor(pasteboard, store, now: { self.t0 })

        monitor.isPaused = true
        pasteboard.copy("secret while paused")
        await monitor.poll()
        monitor.isPaused = false
        await monitor.poll()
        pasteboard.copy("after resume")
        await monitor.poll()

        let items = try await store.search(query: "", limit: 10, offset: 0)
        #expect(items.map(\.text) == ["after resume"])
    }

    @Test func skipsConcealedContent() async throws {
        let pasteboard = FakePasteboard()
        let store = try ClipboardStore(location: .inMemory)
        let monitor = makeMonitor(pasteboard, store, now: { self.t0 })

        pasteboard.copy("hunter2", extraTypes: ["org.nspasteboard.ConcealedType"])
        await monitor.poll()

        let count = try await store.count()
        #expect(count == 0)
    }

    @Test func ownWriteMovesExistingItemToTopWithoutDuplicating() async throws {
        let pasteboard = FakePasteboard()
        let store = try ClipboardStore(location: .inMemory)
        var clock = t0
        let monitor = makeMonitor(pasteboard, store, now: { clock })

        pasteboard.copy("first")
        await monitor.poll()
        clock = t0.addingTimeInterval(5)
        pasteboard.copy("second")
        await monitor.poll()
        clock = t0.addingTimeInterval(10)
        pasteboard.copy("first", extraTypes: [CaptureFilter.ownWriteType])
        await monitor.poll()

        let items = try await store.search(query: "", limit: 10, offset: 0)
        #expect(items.map(\.text) == ["first", "second"])
        #expect(items.first?.lastUsedAt == t0.addingTimeInterval(10))
    }
}
