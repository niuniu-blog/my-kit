import Foundation

@MainActor
public final class ClipboardPanelViewModel: ObservableObject {
    @Published public private(set) var query = ""
    @Published public private(set) var items: [ClipboardItem] = []
    @Published public private(set) var selectedIndex = 0
    /// 面板底部的一行提示（例如未授权时的说明）
    @Published public var footerMessage: String?

    private let store: ClipboardStore
    private let pageSize: Int
    private let debounce: Duration
    private var hasMore = false
    private var isLoadingMore = false
    /// 每次重新搜索加一；异步结果回来时如果代数变了，说明结果已过时，丢弃。
    private var generation = 0
    private var searchTask: Task<Void, Never>?

    public init(store: ClipboardStore, pageSize: Int = 50, debounce: Duration = .milliseconds(80)) {
        self.store = store
        self.pageSize = pageSize
        self.debounce = debounce
    }

    public var selectedItem: ClipboardItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    /// ⌘1–⌘9 对应列表前 9 行。
    public func item(atShortcut number: Int) -> ClipboardItem? {
        guard (1...9).contains(number), items.indices.contains(number - 1) else { return nil }
        return items[number - 1]
    }

    /// 输入框文字变化时调用：防抖后重新搜索。
    public func updateQuery(_ newQuery: String) {
        guard newQuery != query else { return }
        query = newQuery
        searchTask?.cancel()
        searchTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    /// 每次打开面板时调用：清空搜索词和提示，加载最新一页。
    public func reset() async {
        searchTask?.cancel()
        query = ""
        footerMessage = nil
        await reload()
    }

    public func reload() async {
        generation += 1
        let expected = generation
        let result = (try? await store.search(query: query, limit: pageSize, offset: 0)) ?? []
        guard expected == generation else { return }
        items = result
        selectedIndex = 0
        hasMore = result.count == pageSize
    }

    public func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let expected = generation
        let more = (try? await store.search(query: query, limit: pageSize, offset: items.count)) ?? []
        guard expected == generation else { return }
        items.append(contentsOf: more)
        hasMore = more.count == pageSize
    }

    public func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), items.count - 1)
    }

    public func select(index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    public func deleteSelected() async {
        guard let item = selectedItem else { return }
        try? await store.delete(id: item.id)
        items.removeAll { $0.id == item.id }
        selectedIndex = min(selectedIndex, max(items.count - 1, 0))
    }
}
