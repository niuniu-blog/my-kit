import AppKit
import Core
import SwiftUI

/// 系统监控：菜单栏上的 "CPU 12%  内存 63%"，以及菜单顶部的总数和前 5 名排行。
@MainActor
public final class SystemMonitorModule: NSObject, AppModule {
    public let id = "monitor"
    public let name = "系统监控"

    /// 菜单栏标题变了（nil = 不显示文字）。外壳把它交给 StatusBarController.setTitle。
    public var onMenuBarTitleChange: ((NSAttributedString?) -> Void)?
    /// 最近一次的菜单栏标题。外壳创建好状态栏之后用它补上第一次的显示。
    public private(set) var currentMenuBarTitle: NSAttributedString?

    static let activityMonitorPath = "/System/Applications/Utilities/Activity Monitor.app"

    let engine: MonitorEngine
    private let defaults: UserDefaults
    private let settings: MonitorSettings
    private let icons = AppIconCache()
    private var settingsObserver: NSObjectProtocol?

    let cpuHeader = MonitorHeaderView(title: "CPU")
    let memoryHeader = MonitorHeaderView(title: "内存")
    let cpuRows: [MonitorRowView] = (0..<TopProcesses.limit).map { _ in MonitorRowView() }
    let memoryRows: [MonitorRowView] = (0..<TopProcesses.limit).map { _ in MonitorRowView() }
    private var cpuRowItems: [NSMenuItem] = []
    private var memoryRowItems: [NSMenuItem] = []

    /// usesTimer = false、firstCPUListDelay = 0 只在测试里用。
    public init(
        defaults: UserDefaults = .standard,
        host: HostStatsReading = HostStatsReader(),
        processes: ProcessSampling = ProcessSampler(),
        firstCPUListDelay: TimeInterval = 1.0,
        usesTimer: Bool = true
    ) {
        self.defaults = defaults
        self.settings = MonitorSettings(defaults: defaults)
        self.engine = MonitorEngine(
            host: host, processes: processes, settings: MonitorSettings(defaults: defaults),
            firstCPUListDelay: firstCPUListDelay, usesTimer: usesTimer)
        super.init()

        engine.onTotals = { [weak self] totals in self?.show(totals) }
        engine.onTopLists = { [weak self] lists in self?.show(lists) }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: MonitorSettings.didChangeNotification, object: defaults, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.settingsChanged()
            }
        }
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    public func start() throws {
        engine.start()
        show(engine.lastTotals)
    }

    public func stop() {
        engine.stop()
    }

    public func menuWillOpen() {
        resetLists()
        Task { [engine] in
            await engine.menuDidOpen()
        }
    }

    public func menuDidClose() {
        engine.setMenuOpen(false)
    }

    // MARK: 菜单与设置

    public private(set) lazy var menuItems: [NSMenuItem] = {
        func viewItem(_ view: NSView) -> NSMenuItem {
            let item = NSMenuItem()
            item.view = view
            return item
        }
        cpuRowItems = cpuRows.map(viewItem)
        memoryRowItems = memoryRows.map(viewItem)
        let activityMonitor = NSMenuItem(title: "打开活动监视器…", action: #selector(openActivityMonitor), keyEquivalent: "")
        activityMonitor.target = self
        resetLists()
        return [viewItem(cpuHeader)] + cpuRowItems + [viewItem(memoryHeader)] + memoryRowItems + [activityMonitor]
    }()

    public var settingsView: AnyView? {
        AnyView(MonitorSettingsView(defaults: defaults))
    }

    @objc private func openActivityMonitor() {
        let url = URL(fileURLWithPath: Self.activityMonitorPath)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                Toast.show("无法打开活动监视器")
            }
        }
    }

    // MARK: 显示

    /// 菜单栏标题：等宽数字（数值变化时宽度不抖动），达到告警线的数字标红。
    static func attributedTitle(for segments: [MonitorFormat.TitleSegment]) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let result = NSMutableAttributedString(string: " ", attributes: [.font: font])      // 和图标之间留一点空
        for segment in segments {
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if segment.isWarning {
                attributes[.foregroundColor] = NSColor.systemRed
            }
            result.append(NSAttributedString(string: segment.text, attributes: attributes))
        }
        return result
    }

    private func show(_ totals: MonitorEngine.Totals) {
        let cpu = totals.cpu
        let cpuDetail = cpu.map { "用户 \(MonitorFormat.percent($0.user))   系统 \(MonitorFormat.percent($0.system))" } ?? ""
        cpuHeader.update(value: MonitorFormat.percent(cpu?.total), detail: cpuDetail, isWarning: MonitorFormat.isWarning(cpu?.total))

        let memory = totals.memory
        let memoryDetail = memory.map { MonitorFormat.memorySummary(usedBytes: $0.usedBytes, totalBytes: $0.totalBytes) } ?? ""
        memoryHeader.update(value: MonitorFormat.percent(memory?.percent), detail: memoryDetail, isWarning: MonitorFormat.isWarning(memory?.percent))

        updateMenuBarTitle()
    }

    private func updateMenuBarTitle() {
        let totals = engine.lastTotals
        let title: NSAttributedString? = settings.showInMenuBar
            ? Self.attributedTitle(for: MonitorFormat.titleSegments(cpu: totals.cpu?.total, memory: totals.memory?.percent))
            : nil
        currentMenuBarTitle = title
        onMenuBarTitleChange?(title)
    }

    private func show(_ lists: MonitorEngine.TopLists) {
        _ = menuItems
        if let cpu = lists.cpu {
            fill(cpuRows, cpuRowItems, with: cpu, emptyText: "暂无明显占用") { MonitorFormat.percentOneDecimal($0) }
        } else {
            showPlaceholder("正在统计…", in: cpuRows, cpuRowItems)
        }
        fill(memoryRows, memoryRowItems, with: lists.memory, emptyText: "暂无数据") { MonitorFormat.bytes(UInt64($0)) }
    }

    /// 菜单每次打开前：先回到"正在统计…"，不显示上一次打开时的旧排行。
    private func resetLists() {
        showPlaceholder("正在统计…", in: cpuRows, cpuRowItems)
        showPlaceholder("正在统计…", in: memoryRows, memoryRowItems)
    }

    private func fill(
        _ rows: [MonitorRowView], _ items: [NSMenuItem], with entries: [TopEntry],
        emptyText: String, format: (Double) -> String
    ) {
        guard !entries.isEmpty else {
            showPlaceholder(emptyText, in: rows, items)
            return
        }
        for (index, row) in rows.enumerated() {
            let isUsed = index < entries.count
            if isUsed {
                let entry = entries[index]
                let app = icons.entry(for: entry.group)
                row.show(icon: app.icon, name: app.name, value: format(entry.value))
            }
            if items.indices.contains(index) {
                items[index].isHidden = !isUsed        // 不足 5 个时，多余的行隐藏
            }
        }
    }

    private func showPlaceholder(_ text: String, in rows: [MonitorRowView], _ items: [NSMenuItem]) {
        for (index, row) in rows.enumerated() {
            if index == 0 {
                row.showPlaceholder(text)
            }
            if items.indices.contains(index) {
                items[index].isHidden = index != 0
            }
        }
    }

    private func settingsChanged() {
        engine.applySettings()
        engine.refreshTotals()        // 刚从"不显示"切回来时马上读一次，不用等一个间隔（会经 onTotals 刷新标题）
        updateMenuBarTitle()
    }
}
