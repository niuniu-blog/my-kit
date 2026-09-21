import AppKit
import Foundation
import Testing
@testable import SystemMonitorModule

private final class StubHost: HostStatsReading {
    var ticks: [CPUTicks]
    var memory: MemoryUsage?

    init(ticks: [CPUTicks], memory: MemoryUsage?) {
        self.ticks = ticks
        self.memory = memory
    }

    func cpuTicks() -> CPUTicks? {
        ticks.count > 1 ? ticks.removeFirst() : ticks.first
    }

    func memoryUsage() -> MemoryUsage? { memory }
}

private final class StubSampler: ProcessSampling, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [ProcessSnapshot]

    init(_ snapshots: [ProcessSnapshot]) {
        self.snapshots = snapshots
    }

    func sampleAll() -> ProcessSnapshot {
        lock.lock(); defer { lock.unlock() }
        return snapshots.count > 1 ? snapshots.removeFirst() : snapshots[0]
    }
}

@MainActor
@Suite struct SystemMonitorModuleTests {
    private let gigabyte: UInt64 = 1_073_741_824
    private let second: UInt64 = 1_000_000_000

    private func makeDefaults() -> UserDefaults {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func ticks(user: UInt32, system: UInt32, idle: UInt32) -> CPUTicks {
        CPUTicks(cores: [CoreTicks(user: user, system: system, idle: idle, nice: 0)])
    }

    private func snapshot(atSecond time: UInt64, finderCPUMilliseconds: UInt64) -> ProcessSnapshot {
        ProcessSnapshot(
            samples: [
                ProcessSample(pid: 1, cpuNanoseconds: finderCPUMilliseconds * 1_000_000, footprintBytes: 3 * gigabyte,
                              path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"),
                ProcessSample(pid: 2, cpuNanoseconds: 0, footprintBytes: 512 * 1_048_576, path: "/usr/local/bin/node"),
            ],
            timestampNanoseconds: time * second)
    }

    private func makeModule(
        defaults: UserDefaults,
        ticks: [CPUTicks]? = nil,
        memory: MemoryUsage? = nil,
        snapshots: [ProcessSnapshot]? = nil
    ) -> SystemMonitorModule {
        let host = StubHost(
            ticks: ticks ?? [self.ticks(user: 0, system: 0, idle: 0), self.ticks(user: 20, system: 5, idle: 75)],
            memory: memory ?? MemoryUsage(usedBytes: 8 * gigabyte, totalBytes: 16 * gigabyte))
        let sampler = StubSampler(snapshots ?? [
            snapshot(atSecond: 10, finderCPUMilliseconds: 1000),
            snapshot(atSecond: 11, finderCPUMilliseconds: 1284),
        ])
        return SystemMonitorModule(defaults: defaults, host: host, processes: sampler, firstCPUListDelay: 0, usesTimer: false)
    }

    @Test func exposesIdentityMenuAndSettings() {
        let module = makeModule(defaults: makeDefaults())      // 菜单项的 target 是弱引用，模块必须活着
        let items = module.menuItems

        #expect(module.id == "monitor")
        #expect(module.name == "系统监控")
        #expect(module.settingsView != nil)
        #expect(items.count == 13)                             // 2 个标题行 + 10 个排行行 + 打开活动监视器
        #expect(items[0].view === module.cpuHeader)
        #expect(items[6].view === module.memoryHeader)
        #expect(items[12].title == "打开活动监视器…")
        #expect(items[12].target != nil)
        #expect(items[12].action != nil)
        #expect(FileManager.default.fileExists(atPath: SystemMonitorModule.activityMonitorPath))
    }

    @Test func menuBarTitleAppearsOnStartAndGetsCPUOnTheNextTick() async throws {
        let module = makeModule(defaults: makeDefaults())
        var titles: [String?] = []
        module.onMenuBarTitleChange = { titles.append($0?.string) }

        try module.start()
        #expect(module.currentMenuBarTitle?.string == " CPU --  内存 50%")

        await module.engine.tick()
        #expect(module.currentMenuBarTitle?.string == " CPU 25%  内存 50%")
        #expect(titles == [" CPU --  内存 50%", " CPU 25%  内存 50%"])       // 内容没变就不重复通知
    }

    @Test func unchangedTitleDoesNotRelayoutTheStatusItem() async throws {
        // 数值没变时不应该再让菜单栏重新排版文字（那是平时最贵的一步）
        let flat = [ticks(user: 0, system: 0, idle: 0), ticks(user: 20, system: 5, idle: 75), ticks(user: 40, system: 10, idle: 150)]
        let module = makeModule(defaults: makeDefaults(), ticks: flat)
        var notifications = 0
        module.onMenuBarTitleChange = { _ in notifications += 1 }

        try module.start()
        await module.engine.tick()          // CPU 25%
        let afterFirstValue = notifications
        await module.engine.tick()          // 仍然是 25%
        await module.engine.tick()

        #expect(notifications == afterFirstValue)
    }

    @Test func headersShowTotalsWithDetails() async throws {
        let module = makeModule(defaults: makeDefaults())
        try module.start()
        await module.engine.tick()

        #expect(module.cpuHeader.valueLabel.stringValue == "25%")
        #expect(module.cpuHeader.detailLabel.stringValue == "用户 20%   系统 5%")
        #expect(module.memoryHeader.valueLabel.stringValue == "50%")
        #expect(module.memoryHeader.detailLabel.stringValue == "8.0 / 16 GB")
    }

    @Test func numbersAtOrAboveEightyFivePercentAreRed() async throws {
        let module = makeModule(
            defaults: makeDefaults(),
            ticks: [ticks(user: 0, system: 0, idle: 0), ticks(user: 90, system: 0, idle: 10)],
            memory: MemoryUsage(usedBytes: 4 * gigabyte, totalBytes: 16 * gigabyte))
        try module.start()
        await module.engine.tick()

        let title = try #require(module.currentMenuBarTitle)
        let text = title.string as NSString
        let cpuColor = title.attribute(.foregroundColor, at: text.range(of: "90%").location, effectiveRange: nil) as? NSColor
        let memoryColor = title.attribute(.foregroundColor, at: text.range(of: "25%").location, effectiveRange: nil) as? NSColor
        let font = title.attribute(.font, at: text.range(of: "90%").location, effectiveRange: nil) as? NSFont

        #expect(cpuColor == NSColor.systemRed)
        #expect(memoryColor == nil)                            // 没到告警线：用菜单栏默认颜色
        #expect(font == NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular))
        #expect(module.cpuHeader.valueLabel.textColor == NSColor.systemRed)
        #expect(module.memoryHeader.valueLabel.textColor == NSColor.labelColor)
    }

    @Test func turningOffMenuBarDisplayRemovesTheTitleAndTurningOnBringsItBack() throws {
        let defaults = makeDefaults()
        let module = makeModule(defaults: defaults)
        try module.start()
        #expect(module.currentMenuBarTitle != nil)

        MonitorSettings(defaults: defaults).showInMenuBar = false
        #expect(module.currentMenuBarTitle == nil)
        #expect(!module.engine.wantsTimer)

        MonitorSettings(defaults: defaults).showInMenuBar = true
        #expect(module.currentMenuBarTitle?.string.contains("内存 50%") == true)
        #expect(module.engine.wantsTimer)
    }

    @Test func openingTheMenuFirstShowsCountingPlaceholders() throws {
        let module = makeModule(defaults: makeDefaults())
        let items = module.menuItems
        try module.start()

        module.menuWillOpen()      // 同步部分：先把两个榜都重置成"正在统计…"（采样在后台任务里进行）

        #expect(module.cpuRows[0].nameLabel.stringValue == "正在统计…")
        #expect(module.memoryRows[0].nameLabel.stringValue == "正在统计…")
        #expect(items[1...5].map(\.isHidden) == [false, true, true, true, true])
        #expect(items[7...11].map(\.isHidden) == [false, true, true, true, true])
    }

    @Test func listsShowRankedAppsAndHideUnusedRows() async throws {
        let module = makeModule(defaults: makeDefaults())
        let items = module.menuItems
        try module.start()

        await module.engine.menuDidOpen()      // 直接驱动引擎，不经过 menuWillOpen 的后台任务，结果是确定的

        // CPU 榜：Finder 284 毫秒 / 1 秒 = 28.4%；node 是 0%，不上榜
        #expect(module.cpuRows[0].valueLabel.stringValue == "28.4%")
        #expect(module.cpuRows[0].iconView.image != nil)
        #expect(!module.cpuRows[0].nameLabel.stringValue.isEmpty)
        #expect(items[1...5].map(\.isHidden) == [false, true, true, true, true])
        // 内存榜：Finder 3 GB、node 512 MB
        #expect(module.memoryRows[0].valueLabel.stringValue == "3.0 GB")
        #expect(module.memoryRows[1].nameLabel.stringValue == "node")
        #expect(module.memoryRows[1].valueLabel.stringValue == "512 MB")
        #expect(items[7...11].map(\.isHidden) == [false, false, true, true, true])
    }

    @Test func closingTheMenuStopsProcessSampling() async throws {
        let module = makeModule(defaults: makeDefaults())
        try module.start()
        await module.engine.menuDidOpen()
        #expect(module.engine.isMenuOpen)

        module.menuDidClose()

        #expect(!module.engine.isMenuOpen)
    }

    @Test func idleSystemShowsAFriendlyLineInsteadOfAnEmptyCPUList() async throws {
        let quiet = [snapshot(atSecond: 10, finderCPUMilliseconds: 1000), snapshot(atSecond: 11, finderCPUMilliseconds: 1000)]
        let module = makeModule(defaults: makeDefaults(), snapshots: quiet)
        _ = module.menuItems
        try module.start()

        await module.engine.menuDidOpen()

        #expect(module.cpuRows[0].nameLabel.stringValue == "暂无明显占用")
        #expect(module.cpuRows[0].valueLabel.stringValue == "")
    }
}

@MainActor
@Suite struct AppIconCacheTests {
    @Test func bundledAppGetsItsDisplayNameAndASixteenPointIcon() {
        let cache = AppIconCache()
        let finder = AppGroup(
            key: "/System/Library/CoreServices/Finder.app", fallbackName: "Finder",
            bundlePath: "/System/Library/CoreServices/Finder.app")

        let entry = cache.entry(for: finder)

        #expect(!entry.name.isEmpty)
        #expect(!entry.name.hasSuffix(".app"))
        #expect(entry.icon.size == AppIconCache.iconSize)
    }

    @Test func plainExecutableUsesItsFileNameAndAGenericIcon() {
        let entry = AppIconCache().entry(for: AppGroup(key: "node", fallbackName: "node", bundlePath: nil))
        #expect(entry.name == "node")
        #expect(entry.icon.size == AppIconCache.iconSize)
    }

    @Test func missingBundleFallsBackToTheGroupName() {
        let gone = AppGroup(key: "/Applications/Gone.app", fallbackName: "Gone", bundlePath: "/Applications/Gone.app")
        #expect(AppIconCache().entry(for: gone).name == "Gone")
    }

    @Test func entriesAreCachedPerGroup() {
        let cache = AppIconCache()
        let group = AppGroup(key: "node", fallbackName: "node", bundlePath: nil)
        #expect(cache.entry(for: group).icon === cache.entry(for: group).icon)
    }
}

@MainActor
@Suite struct MonitorMenuViewsTests {
    @Test func viewsHaveTheFixedMenuWidth() {
        #expect(MonitorHeaderView(title: "CPU").frame.width == MonitorMenuMetrics.width)
        #expect(MonitorRowView().frame.width == MonitorMenuMetrics.width)
    }

    @Test func rowSwitchesBetweenEntryAndPlaceholder() {
        let row = MonitorRowView()
        row.show(icon: NSImage(size: NSSize(width: 16, height: 16)), name: "微信", value: "6.1%")
        #expect(row.nameLabel.stringValue == "微信")
        #expect(row.valueLabel.stringValue == "6.1%")
        #expect(row.nameLabel.textColor == NSColor.labelColor)

        row.showPlaceholder("正在统计…")
        #expect(row.iconView.image == nil)
        #expect(row.valueLabel.stringValue == "")
        #expect(row.nameLabel.textColor == NSColor.secondaryLabelColor)
    }

    @Test func labelsStayInsideTheView() {
        let header = MonitorHeaderView(title: "内存")
        let row = MonitorRowView()
        #expect(header.detailLabel.frame.maxX <= MonitorMenuMetrics.width)
        #expect(row.valueLabel.frame.maxX <= MonitorMenuMetrics.width)
        #expect(row.nameLabel.frame.maxX <= row.valueLabel.frame.minX)
    }
}
