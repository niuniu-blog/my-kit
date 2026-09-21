import Foundation
import Testing
@testable import ClipboardModule

@MainActor
@Suite struct ClipboardPanelViewModelTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// 依次插入 texts，越靠后的越新。
    private func makeViewModel(_ texts: [String], pageSize: Int = 50) async throws -> (ClipboardPanelViewModel, ClipboardStore) {
        let store = try ClipboardStore(location: .inMemory)
        for (offset, text) in texts.enumerated() {
            try await store.add(text: text, appBundleID: nil, appName: nil, at: t0.addingTimeInterval(Double(offset)))
        }
        let viewModel = ClipboardPanelViewModel(store: store, pageSize: pageSize, debounce: .milliseconds(1))
        return (viewModel, store)
    }

    @Test func resetLoadsNewestFirstAndSelectsFirstRow() async throws {
        let (vm, _) = try await makeViewModel(["a", "b", "c"])

        await vm.reset()

        #expect(vm.items.map(\.text) == ["c", "b", "a"])
        #expect(vm.selectedIndex == 0)
        #expect(vm.selectedItem?.text == "c")
    }

    @Test func resetClearsQueryFooterAndSelection() async throws {
        let (vm, _) = try await makeViewModel(["apple pie", "banana"])
        vm.updateQuery("apple")
        await vm.reload()
        vm.footerMessage = "提示"

        await vm.reset()

        #expect(vm.query == "")
        #expect(vm.footerMessage == nil)
        #expect(vm.items.count == 2)
    }

    @Test func reloadFiltersByQuery() async throws {
        let (vm, _) = try await makeViewModel(["apple pie", "banana", "apple juice"])

        vm.updateQuery("apple")
        await vm.reload()

        #expect(vm.items.map(\.text) == ["apple juice", "apple pie"])
        #expect(vm.selectedIndex == 0)
    }

    @Test func updateQueryTriggersDebouncedSearch() async throws {
        let (vm, _) = try await makeViewModel(["apple pie", "banana"])
        await vm.reset()

        vm.updateQuery("banana")
        try await Task.sleep(for: .milliseconds(200))

        #expect(vm.items.map(\.text) == ["banana"])
    }

    @Test func moveSelectionClampsToBounds() async throws {
        let (vm, _) = try await makeViewModel(["a", "b", "c"])
        await vm.reset()

        vm.moveSelection(by: -1)
        #expect(vm.selectedIndex == 0)
        vm.moveSelection(by: 1)
        vm.moveSelection(by: 1)
        vm.moveSelection(by: 1)
        #expect(vm.selectedIndex == 2)
    }

    @Test func moveSelectionOnEmptyListIsNoOp() async throws {
        let (vm, _) = try await makeViewModel([])
        await vm.reset()
        vm.moveSelection(by: 1)
        #expect(vm.selectedIndex == 0)
        #expect(vm.selectedItem == nil)
    }

    @Test func selectIgnoresOutOfRangeIndex() async throws {
        let (vm, _) = try await makeViewModel(["a", "b"])
        await vm.reset()
        vm.select(index: 1)
        #expect(vm.selectedIndex == 1)
        vm.select(index: 9)
        #expect(vm.selectedIndex == 1)
    }

    @Test func shortcutNumbersMapToFirstNineRows() async throws {
        let (vm, _) = try await makeViewModel(["a", "b", "c"])
        await vm.reset()

        #expect(vm.item(atShortcut: 1)?.text == "c")
        #expect(vm.item(atShortcut: 3)?.text == "a")
        #expect(vm.item(atShortcut: 4) == nil)
        #expect(vm.item(atShortcut: 0) == nil)
        #expect(vm.item(atShortcut: 10) == nil)
    }

    @Test func deleteSelectedRemovesFromListAndStore() async throws {
        let (vm, store) = try await makeViewModel(["a", "b", "c"])
        await vm.reset()
        vm.moveSelection(by: 2)            // 选中最后一行 "a"

        await vm.deleteSelected()

        #expect(vm.items.map(\.text) == ["c", "b"])
        #expect(vm.selectedIndex == 1)     // 选中项回退到新的最后一行
        let remaining = try await store.count()
        #expect(remaining == 2)
    }

    @Test func deletingLastRemainingItemLeavesEmptyList() async throws {
        let (vm, _) = try await makeViewModel(["only"])
        await vm.reset()
        await vm.deleteSelected()
        #expect(vm.items.isEmpty)
        #expect(vm.selectedIndex == 0)
    }

    @Test func loadMoreAppendsNextPagesUntilExhausted() async throws {
        let (vm, _) = try await makeViewModel(["1", "2", "3", "4", "5"], pageSize: 2)
        await vm.reset()
        #expect(vm.items.map(\.text) == ["5", "4"])

        await vm.loadMore()
        #expect(vm.items.map(\.text) == ["5", "4", "3", "2"])

        await vm.loadMore()
        await vm.loadMore()                // 已经到底，多调用一次也不会重复
        #expect(vm.items.map(\.text) == ["5", "4", "3", "2", "1"])
    }
}
