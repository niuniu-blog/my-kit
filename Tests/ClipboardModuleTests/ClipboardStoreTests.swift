import Foundation
import Testing
@testable import ClipboardModule

@Suite struct ClipboardStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore() throws -> ClipboardStore {
        try ClipboardStore(location: .inMemory)
    }

    @Test func addThenSearchReturnsItemWithAllFields() async throws {
        let store = try makeStore()
        let id = try await store.add(text: "hello world", appBundleID: "com.apple.Safari", appName: "Safari", at: t0)

        let items = try await store.search(query: "", limit: 10, offset: 0)

        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.id == id)
        #expect(item.text == "hello world")
        #expect(item.appBundleID == "com.apple.Safari")
        #expect(item.appName == "Safari")
        #expect(item.createdAt == t0)
        #expect(item.lastUsedAt == t0)
    }

    @Test func emptyQueryReturnsNewestFirst() async throws {
        let store = try makeStore()
        try await store.add(text: "old", appBundleID: nil, appName: nil, at: t0)
        try await store.add(text: "new", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(10))

        let items = try await store.search(query: "", limit: 10, offset: 0)

        #expect(items.map(\.text) == ["new", "old"])
    }

    @Test func duplicateTextMovesToTopInsteadOfInserting() async throws {
        let store = try makeStore()
        let firstID = try await store.add(text: "dup", appBundleID: "a", appName: "A", at: t0)
        try await store.add(text: "other", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(5))
        let secondID = try await store.add(text: "dup", appBundleID: "b", appName: "B", at: t0.addingTimeInterval(10))

        let items = try await store.search(query: "", limit: 10, offset: 0)

        #expect(secondID == firstID)
        #expect(items.map(\.text) == ["dup", "other"])
        #expect(items[0].createdAt == t0)
        #expect(items[0].lastUsedAt == t0.addingTimeInterval(10))
        #expect(items[0].appName == "B")   // 来源更新为最近一次复制的 App
    }

    @Test func touchMovesExistingToTopAndKeepsSourceApp() async throws {
        let store = try makeStore()
        try await store.add(text: "first", appBundleID: "a", appName: "A", at: t0)
        try await store.add(text: "second", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(5))

        let touched = try await store.touch(text: "first", at: t0.addingTimeInterval(10))
        let items = try await store.search(query: "", limit: 10, offset: 0)

        #expect(touched)
        #expect(items.map(\.text) == ["first", "second"])
        #expect(items[0].appName == "A")
    }

    @Test func touchUnknownTextReturnsFalseAndInsertsNothing() async throws {
        let store = try makeStore()
        let touched = try await store.touch(text: "ghost", at: t0)
        #expect(!touched)
        #expect(try await store.count() == 0)
    }

    @Test func ftsSearchMatchesSubstringCaseInsensitively() async throws {
        let store = try makeStore()
        try await store.add(text: "git rebase -i HEAD~3", appBundleID: nil, appName: nil, at: t0)
        try await store.add(text: "SELECT * FROM users", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(1))

        #expect(try await store.search(query: "REBASE", limit: 10, offset: 0).map(\.text) == ["git rebase -i HEAD~3"])
        #expect(try await store.search(query: "from use", limit: 10, offset: 0).map(\.text) == ["SELECT * FROM users"])
    }

    @Test func chineseSubstringSearch() async throws {
        let store = try makeStore()
        try await store.add(text: "北京亚太宏图科技有限公司", appBundleID: nil, appName: nil, at: t0)
        try await store.add(text: "上海某某公司", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(1))

        #expect(try await store.search(query: "亚太宏图", limit: 10, offset: 0).count == 1)   // ≥3 字符走 FTS
        #expect(try await store.search(query: "公司", limit: 10, offset: 0).count == 2)       // 2 字符走 LIKE
        #expect(try await store.search(query: "京", limit: 10, offset: 0).count == 1)         // 1 字符走 LIKE
    }

    @Test func shortQueryTreatsLikeWildcardsLiterally() async throws {
        let store = try makeStore()
        try await store.add(text: "100% sure", appBundleID: nil, appName: nil, at: t0)
        try await store.add(text: "a_b", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(1))
        try await store.add(text: "plain", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(2))

        #expect(try await store.search(query: "%", limit: 10, offset: 0).map(\.text) == ["100% sure"])
        #expect(try await store.search(query: "_", limit: 10, offset: 0).map(\.text) == ["a_b"])
    }

    @Test func ftsSpecialCharactersDoNotThrow() async throws {
        let store = try makeStore()
        try await store.add(text: "say \"hello\" * now", appBundleID: nil, appName: nil, at: t0)

        #expect(try await store.search(query: "\"hello\"", limit: 10, offset: 0).count == 1)
        #expect(try await store.search(query: "* now", limit: 10, offset: 0).count == 1)
        #expect(try await store.search(query: "AND OR NOT", limit: 10, offset: 0).isEmpty)
    }

    @Test func queryIsTrimmedBeforeSearching() async throws {
        let store = try makeStore()
        try await store.add(text: "hello", appBundleID: nil, appName: nil, at: t0)
        #expect(try await store.search(query: "   ", limit: 10, offset: 0).count == 1)
        #expect(try await store.search(query: " hello ", limit: 10, offset: 0).count == 1)
    }

    @Test func paginationWithLimitAndOffset() async throws {
        let store = try makeStore()
        for i in 0..<5 {
            try await store.add(text: "item \(i)", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(Double(i)))
        }

        let page1 = try await store.search(query: "", limit: 2, offset: 0)
        let page2 = try await store.search(query: "", limit: 2, offset: 2)
        let page3 = try await store.search(query: "", limit: 2, offset: 4)

        #expect(page1.map(\.text) == ["item 4", "item 3"])
        #expect(page2.map(\.text) == ["item 2", "item 1"])
        #expect(page3.map(\.text) == ["item 0"])
    }

    @Test func deleteRemovesItemFromListAndFromFTS() async throws {
        let store = try makeStore()
        let id = try await store.add(text: "delete me please", appBundleID: nil, appName: nil, at: t0)

        try await store.delete(id: id)

        #expect(try await store.count() == 0)
        #expect(try await store.search(query: "delete me", limit: 10, offset: 0).isEmpty)
    }

    @Test func purgeRemovesOnlyItemsLastUsedBeforeCutoff() async throws {
        let store = try makeStore()
        try await store.add(text: "expired", appBundleID: nil, appName: nil, at: t0)
        try await store.add(text: "reused", appBundleID: nil, appName: nil, at: t0)
        try await store.add(text: "fresh", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(8 * 86400))
        try await store.touch(text: "reused", at: t0.addingTimeInterval(8 * 86400))

        let removed = try await store.purge(olderThan: t0.addingTimeInterval(86400))

        #expect(removed == 1)
        let remaining = try await store.search(query: "", limit: 10, offset: 0).map(\.text)
        #expect(Set(remaining) == ["reused", "fresh"])
    }

    @Test func clearAllRemovesEverything() async throws {
        let store = try makeStore()
        try await store.add(text: "one two three", appBundleID: nil, appName: nil, at: t0)
        try await store.clearAll()
        #expect(try await store.count() == 0)
        #expect(try await store.search(query: "two", limit: 10, offset: 0).isEmpty)
    }

    @Test func fileStorePersistsAcrossReopen() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mykit-test-\(UUID().uuidString)")
            .appendingPathComponent("clipboard.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let opened = try ClipboardStore.openRecovering(at: url)
            #expect(!opened.recovered)
            try await opened.store.add(text: "persisted", appBundleID: nil, appName: nil, at: t0)
        }
        let reopened = try ClipboardStore.openRecovering(at: url)

        #expect(!reopened.recovered)
        #expect(try await reopened.store.search(query: "", limit: 10, offset: 0).map(\.text) == ["persisted"])
    }

    @Test func corruptFileIsBackedUpAndRecreated() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mykit-test-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("clipboard.sqlite")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(repeating: 0x41, count: 4096).write(to: url)

        let opened = try ClipboardStore.openRecovering(at: url, now: t0)

        #expect(opened.recovered)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("clipboard.sqlite.corrupt-1800000000").path))
        try await opened.store.add(text: "works again", appBundleID: nil, appName: nil, at: t0)
        #expect(try await opened.store.count() == 1)
    }
}
