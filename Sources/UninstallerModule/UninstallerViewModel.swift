import Foundation
import SwiftUI

/// 卸载窗口背后的全部状态。所有会碰系统的操作都通过 UninstallerDependencies 注入。
@MainActor
public final class UninstallerViewModel: ObservableObject {
    public enum Phase: Equatable {
        /// 还没选软件
        case idle
        case scanning
        /// 清单已经列出，等用户决定
        case ready
        /// 目标软件正在运行，等用户同意退出它
        case needsQuit
        /// 已经请它退出，正在等
        case quitting
        /// 等用户在确认框里点"移到废纸篓"
        case confirming
        case running
        case finished(TrashReport)
    }

    public struct ItemGroup: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let items: [LeftoverItem]
    }

    @Published public private(set) var apps: [InstalledApp] = []
    @Published public var query = ""
    @Published public var sortOrder: AppListing.SortOrder = .name
    @Published public private(set) var isLoadingApps = false
    @Published public private(set) var selectedApp: InstalledApp?
    @Published public private(set) var items: [LeftoverItem] = []
    @Published public private(set) var checkedIDs: Set<String> = []
    /// 清单里当前高亮的那一行（「在访达中显示」针对它）
    @Published public var highlightedItemID: String?
    @Published public private(set) var unreadableLocations: [URL] = []
    @Published public private(set) var phase: Phase = .idle
    /// 窗口里的一行提示（拖进了系统软件、软件没能退出……）
    @Published public var notice: String?

    private let dependencies: UninstallerDependencies
    private var allBundleIDs: Set<String> = []
    private var selectionGeneration = 0
    private var scanFlag = CancellationFlag()
    private var appSizeFlag = CancellationFlag()
    private var isTornDown = false

    public init(dependencies: UninstallerDependencies) {
        self.dependencies = dependencies
    }

    // MARK: 软件列表

    public var visibleApps: [InstalledApp] {
        AppListing.sorted(AppListing.filter(apps, query: query), by: sortOrder)
    }

    /// 窗口打开时调用：先列出软件，再在后台逐个算大小。
    public func start() {
        Task {
            await load()
            await computeAppSizes()
        }
    }

    public func load() async {
        isLoadingApps = true
        let listApps = dependencies.listApps
        let list = await Task.detached(priority: .userInitiated) { listApps() }.value
        guard !isTornDown else { return }
        apps = list.apps
        allBundleIDs = list.allBundleIDs
        isLoadingApps = false
    }

    /// 逐个计算大小，算好一个显示一个。窗口关闭时停止。
    public func computeAppSizes() async {
        let flag = appSizeFlag
        let sizeOf = dependencies.sizeOf
        for app in apps where app.sizeBytes == nil {
            if flag.isCancelled { return }
            let url = app.identity.url
            let size = await Task.detached(priority: .utility) { sizeOf(url, { flag.isCancelled }) }.value
            if flag.isCancelled { return }
            if let size, let index = apps.firstIndex(where: { $0.id == app.id }) {
                apps[index].sizeBytes = size
            }
        }
    }

    // MARK: 选择与清单

    /// 选中一个软件并扫描它的相关文件。再次调用会取消上一次还没完成的扫描。
    public func select(_ app: InstalledApp?) async {
        scanFlag.cancel()
        let flag = CancellationFlag()
        scanFlag = flag
        selectionGeneration += 1
        let generation = selectionGeneration

        selectedApp = app
        items = []
        checkedIDs = []
        unreadableLocations = []
        highlightedItemID = nil
        notice = nil
        guard let app else {
            phase = .idle
            return
        }

        phase = .scanning
        let scan = dependencies.scanLeftovers
        let identity = app.identity
        let others = allBundleIDs.subtracting([identity.bundleID].compactMap { $0 })
        let result = await Task.detached(priority: .userInitiated) {
            scan(identity, others, { flag.isCancelled })
        }.value
        guard generation == selectionGeneration, !flag.isCancelled else { return }

        var found = result.items
        if let knownSize = app.sizeBytes, let index = found.firstIndex(where: { $0.isAppBundle }) {
            found[index].sizeBytes = knownSize            // 列表里已经算过，不再重算
        }
        items = found
        unreadableLocations = result.unreadableLocations
        checkedIDs = Set(found.filter { $0.confidence == .certain }.map(\.id))
        phase = .ready

        let sizeOf = dependencies.sizeOf
        for item in found where item.sizeBytes == nil {
            let url = item.url
            let size = await Task.detached(priority: .utility) { sizeOf(url, { flag.isCancelled }) }.value
            guard generation == selectionGeneration, !flag.isCancelled else { return }
            if let size, let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].sizeBytes = size
            }
        }
    }

    /// 三组：确定相关 / 可能相关 / 需要管理员密码。组内软件本体在最前，其余按大小从大到小。
    public var groups: [ItemGroup] {
        func ordered(_ list: [LeftoverItem]) -> [LeftoverItem] {
            list.sorted { first, second in
                if first.isAppBundle != second.isAppBundle { return first.isAppBundle }
                let a = first.sizeBytes ?? 0
                let b = second.sizeBytes ?? 0
                if a != b { return a > b }
                return first.url.path < second.url.path
            }
        }
        let certain = items.filter { !$0.needsAdmin && $0.confidence == .certain }
        let possible = items.filter { !$0.needsAdmin && $0.confidence == .possible }
        let admin = items.filter(\.needsAdmin)
        return [
            ItemGroup(id: "certain", title: "确定相关", items: ordered(certain)),
            ItemGroup(id: "possible", title: "可能相关（默认不勾选，请自己判断）", items: ordered(possible)),
            ItemGroup(id: "admin", title: "需要管理员密码", items: ordered(admin)),
        ].filter { !$0.items.isEmpty }
    }

    public func isChecked(_ item: LeftoverItem) -> Bool {
        checkedIDs.contains(item.id)
    }

    public func setChecked(_ item: LeftoverItem, _ checked: Bool) {
        guard phase == .ready else { return }
        if checked {
            checkedIDs.insert(item.id)
        } else {
            checkedIDs.remove(item.id)
        }
    }

    public func selectAll() {
        guard phase == .ready else { return }
        checkedIDs = Set(items.map(\.id))
    }

    public func selectOnlyCertain() {
        guard phase == .ready else { return }
        checkedIDs = Set(items.filter { $0.confidence == .certain }.map(\.id))
    }

    public var checkedItems: [LeftoverItem] {
        items.filter { checkedIDs.contains($0.id) }
    }

    public var checkedBytes: UInt64 {
        checkedItems.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
    }

    /// 标题行："已选 9 项，2.3 GB"
    public var summaryText: String {
        "已选 \(checkedItems.count) 项，\(SizeCalculator.format(checkedBytes))"
    }

    public var confirmationText: String {
        "将把 \(checkedItems.count) 项（\(SizeCalculator.format(checkedBytes))）移到废纸篓。可以从废纸篓恢复。"
    }

    public var canUninstall: Bool {
        phase == .ready && !checkedItems.isEmpty
    }

    public var highlightedItem: LeftoverItem? {
        items.first { $0.id == highlightedItemID }
    }

    // MARK: 执行

    /// 点了「移到废纸篓」。要移走软件本体而它正在运行 → 先请用户同意退出它。
    public func requestUninstall() {
        guard canUninstall, let app = selectedApp else { return }
        notice = nil
        if checkedItems.contains(where: \.isAppBundle), dependencies.isRunning(app.identity) {
            phase = .needsQuit
        } else {
            phase = .confirming
        }
    }

    public func quitAndContinue() async {
        guard phase == .needsQuit, let app = selectedApp else { return }
        phase = .quitting               // 立刻离开 needsQuit：提示框关掉后不会因为状态没变又弹出来
        if await dependencies.quit(app.identity) {
            phase = .confirming
        } else {
            notice = "「\(app.title)」没有退出，请手动退出它之后再试"
            phase = .ready
        }
    }

    /// 在"需要退出"或确认框里点了取消。
    public func cancelPending() {
        if phase == .needsQuit || phase == .confirming {
            phase = .ready
        }
    }

    public func confirm() async {
        guard beginRunning() else { return }
        await performTrash()
    }

    /// 给界面上的按钮用的同步入口：点下去的同一时刻状态就变了，确认框不会重复弹出。
    public func confirmTapped() {
        guard beginRunning() else { return }
        Task { await performTrash() }
    }

    public func quitTapped() {
        Task { await quitAndContinue() }
    }

    private func beginRunning() -> Bool {
        guard phase == .confirming, selectedApp != nil else { return false }
        phase = .running
        return true
    }

    private func performTrash() async {
        guard let app = selectedApp else { return }
        let toTrash = checkedItems
        let trash = dependencies.trash
        let identity = app.identity
        let report = await Task.detached(priority: .userInitiated) { trash(toTrash, identity) }.value
        guard !isTornDown else { return }
        phase = .finished(report)
    }

    /// 关掉结果页。软件本体已经移走 → 从列表里去掉它；否则重新扫描一遍，显示还剩什么。
    public func dismissResult() async {
        guard case .finished(let report) = phase, let app = selectedApp else { return }
        if report.removedAppBundle {
            apps.removeAll { $0.id == app.id }
            if let bundleID = app.identity.bundleID { allBundleIDs.remove(bundleID) }
            await select(nil)
        } else {
            await select(app)
        }
    }

    // MARK: 拖放

    /// 返回 false = 不是 .app，忽略。
    @discardableResult
    public func handleDrop(_ url: URL) async -> Bool {
        guard url.pathExtension.lowercased() == "app" else { return false }
        guard phase != .running else { return true }
        guard let dropped = dependencies.makeApp(url) else {
            notice = "读不出这个软件的信息，无法卸载"
            return true
        }
        if dependencies.isProtected(url, dropped.identity.bundleID) {
            notice = "这是系统软件，不能卸载"
            return true
        }
        let app: InstalledApp
        if let existing = apps.first(where: { $0.id == dropped.id }) {
            app = existing
        } else {
            apps.append(dropped)
            app = dropped
        }
        await select(app)
        return true
    }

    // MARK: 收尾

    /// 窗口关闭：停掉后台工作，放掉全部数据。
    public func teardown() {
        isTornDown = true
        scanFlag.cancel()
        appSizeFlag.cancel()
        selectionGeneration += 1
        apps = []
        allBundleIDs = []
        selectedApp = nil
        items = []
        checkedIDs = []
        unreadableLocations = []
        highlightedItemID = nil
        notice = nil
        phase = .idle
    }
}
