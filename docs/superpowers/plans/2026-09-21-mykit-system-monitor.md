# MyKit 系统监控模块（CPU、内存）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 MyKit 增加系统监控：菜单栏图标旁常驻显示 `CPU 12%  内存 63%`，点开菜单在最顶部看到 CPU / 内存总数和各自最占资源的 5 个软件（带图标、辅助进程合并到所属软件），并可打开"活动监视器"。

**Architecture:** 新增 Target `SystemMonitorModule`（依赖 `Core`）。纯计算（tick 差值 → CPU 占用、内存口径、路径 → 软件归组、排行、格式化）与系统读取（`HostStatsReader`、`ProcessSampler` 两个薄包装）分离；`MonitorEngine` 负责"什么时候采样"（菜单栏显示开着才跑一个定时器，只读两个内核计数器；菜单打开期间才在后台线程采样全部进程）；`SystemMonitorModule` 把引擎的输出变成菜单栏标题和自定义视图的菜单项。外壳只做两处小扩展：`AppModule` 增加菜单开 / 关通知，`StatusBarController` 支持图标旁的文字。

**Tech Stack:** Swift 6.4（语言模式 5）、AppKit、SwiftUI（仅设置页）、Darwin 内核接口（`host_processor_info`、`host_statistics64`、`proc_listallpids`、`proc_pid_rusage`、`proc_pidpath`、`mach_timebase_info`）、Swift Testing。无第三方依赖。

**Spec:** `docs/superpowers/specs/2026-09-21-mykit-system-monitor-design.md`

## Global Constraints

- 运行环境：macOS 27，只有 Command Line Tools，**没有 Xcode**。不要使用 `xcodebuild`、`.xcodeproj`、XCTest。
- 构建必须带 `--build-system native`（会有一条 deprecated 警告，忽略）。跑测试**只用** `scripts/test.sh`；直接 `swift test` 会报 `no such module 'Testing'`。
- 测试框架：Swift Testing（`import Testing`、`@Test`、`#expect`、`#require`）。
- **`#expect` 里不要写字面量算术**（如 `x == 1600 - 16` 会因类型推断失败而误报），先用 `let` 算好或直接写结果；`try` / `await` 的值同理先取出来再比较。
- **不要写 `@State`**（macOS 27 SDK 里是宏，CLT 下没有宏插件）；需要时用 `Core` 里的别名 `@ViewState`。同理不要用 `#Preview`、`@Entry`、`@Animatable`。本计划的设置页只用 `@AppStorage`，不受影响。
- 最低系统 macOS 14；更高版本的 API 必须包在 `#available` 里（本计划没有用到）。
- 不引入任何第三方依赖；不调用 `top`、`ps` 等外部命令；不联网。Swift 语言模式 5；目标是零编译警告。
- 所有界面相关的类型标 `@MainActor`。读两个内核计数器（总数）可以在主线程做；**采样全部进程必须放到后台线程**，结果回到主线程再用；任何时候都不能阻塞菜单的跟踪。
- 常驻开销只允许一个"读总数"的定时器；菜单栏显示关掉且菜单没打开时不得有任何定时器或采样。定时器必须加在 `.common` RunLoop 模式（菜单打开时主 RunLoop 处于事件跟踪模式）。
- 测试不能依赖真实的系统负载，不能碰 `UserDefaults.standard`（用 `UserDefaults(suiteName:)` 的临时域）；读取器的测试只做冒烟检查。
- 所有面向用户的文案用简体中文。
- 终端是 zsh：查日志用 `/usr/bin/log`（`log` 是 zsh 内建命令）；zsh 数组下标从 1 开始。
- 每个任务结束时 `scripts/test.sh` 必须全绿、零警告，然后提交。
- 本计划修改已有文件时一律给出**完整的新文件内容**（整体替换）。动手前先确认工作区干净（`git status`），文件内容与计划写作时一致。

## File Structure

```
Package.swift                              修改  新增 SystemMonitorModule 及其测试 Target；MyKit 依赖它

Sources/Core/
  AppModule.swift                          修改  增加 menuWillOpen() / menuDidClose()（默认空实现）
  ModuleRegistry.swift                     修改  菜单开 / 关转发；menuItemsWithSeparators

Sources/MyKit/
  StatusBarController.swift                修改  可变长度 + setTitle + NSMenuDelegate 回调
  AppDelegate.swift                        修改  Task 1 接菜单回调；Task 5 最先注册监控模块并接标题

Sources/SystemMonitorModule/
  CPULoad.swift                            新增  CoreTicks / CPUTicks / CPULoad.between（含 32 位回绕）
  MemoryUsage.swift                        新增  已用内存口径与百分比
  ProcessGrouping.swift                    新增  AppGroup；路径 → 最外层 .app / 可执行文件名
  TopProcesses.swift                       新增  ProcessSample / TopEntry；CPU 榜、内存榜
  MonitorFormat.swift                      新增  百分比、MB / GB、"10.1 / 16 GB"、标题分段与告警
  MonitorSettings.swift                    新增  是否显示、刷新间隔
  HostStatsReader.swift                    新增  HostStatsReading 协议 + 内核读取
  ProcessSampler.swift                     新增  ProcessSnapshot / ProcessSampling 协议 + 内核读取
  MonitorEngine.swift                      新增  采样调度
  AppIconCache.swift                       新增  软件显示名 + 16pt 图标缓存
  MonitorMenuViews.swift                   新增  标题行视图、排行行视图
  MonitorSettingsView.swift                新增  SwiftUI 设置页
  SystemMonitorModule.swift                新增  AppModule 实现

Tests/CoreTests/ModuleRegistryTests.swift  修改  追加用例
Tests/SystemMonitorModuleTests/
  CPULoadTests.swift / MemoryUsageTests.swift / ProcessGroupingTests.swift /
  TopProcessesTests.swift / MonitorFormatTests.swift / MonitorSettingsTests.swift   新增（Task 2）
  SystemReadersTests.swift                 新增（Task 3）
  MonitorEngineTests.swift                 新增（Task 4）
  SystemMonitorModuleTests.swift           新增（Task 5，含 AppIconCache 与菜单视图的测试）

README.md                                  修改  系统监控一节
```

任务顺序：1 外壳的两处扩展 → 2 纯计算 → 3 系统读取器 → 4 采样调度 → 5 界面、总装、使用说明、验收。

---

### Task 1: 外壳扩展 —— 菜单开 / 关通知、图标旁的文字、每个模块后面一条分隔线

**Files:**
- Modify: `Sources/Core/AppModule.swift`, `Sources/Core/ModuleRegistry.swift`
- Modify: `Sources/MyKit/StatusBarController.swift`, `Sources/MyKit/AppDelegate.swift`
- Test: `Tests/CoreTests/ModuleRegistryTests.swift`

**Interfaces:**
- Consumes: 现有的 `AppModule`、`ModuleRegistry`、`StatusBarController`、`AppDelegate`
- Produces:
  - `AppModule` 新增 `func menuWillOpen()`、`func menuDidClose()`（协议扩展里有空的默认实现，现有模块不用改）
  - `ModuleRegistry.menuWillOpen()` / `menuDidClose()`：只转发给**成功启动**的模块
  - `ModuleRegistry.menuItemsWithSeparators: [NSMenuItem]`：每个有菜单项的模块后面跟一条分隔线
  - `StatusBarController(moduleMenuItems:onOpenSettings:onMenuWillOpen:onMenuDidClose:)`（后两个有默认值）；`func setTitle(_ title: NSAttributedString?)`；状态项改为 `NSStatusItem.variableLength`

这个任务做完，App 的行为和之前一样（菜单里"截图"一组后面多一条分隔线），只是为监控模块铺好路。

- [ ] **Step 1: 在 `Tests/CoreTests/ModuleRegistryTests.swift` 里追加失败的测试（完整文件）**

```swift
import AppKit
import Testing
@testable import Core

@MainActor
private final class FakeModule: AppModule {
    let id: String
    let name: String
    var shouldFail = false
    var log: [String]
    let items: [NSMenuItem]

    init(id: String, items: [NSMenuItem] = [], log: [String] = []) {
        self.id = id
        self.name = id
        self.items = items
        self.log = log
    }

    struct Boom: Error {}

    func start() throws {
        if shouldFail { throw Boom() }
        log.append("start")
    }

    func stop() { log.append("stop") }

    var menuItems: [NSMenuItem] { items }

    func menuWillOpen() { log.append("menuWillOpen") }

    func menuDidClose() { log.append("menuDidClose") }
}

@MainActor
@Suite struct ModuleRegistryTests {
    @Test func startsAndStopsRegisteredModules() {
        let registry = ModuleRegistry()
        let a = FakeModule(id: "a")
        let b = FakeModule(id: "b")
        registry.register(a)
        registry.register(b)

        registry.startAll()
        registry.stopAll()

        #expect(a.log == ["start", "stop"])
        #expect(b.log == ["start", "stop"])
        #expect(registry.failures.isEmpty)
    }

    @Test func failingModuleDoesNotBlockOthersAndIsNotStopped() {
        let registry = ModuleRegistry()
        let bad = FakeModule(id: "bad")
        bad.shouldFail = true
        let good = FakeModule(id: "good")
        registry.register(bad)
        registry.register(good)

        registry.startAll()
        registry.stopAll()

        #expect(registry.failures.map(\.id) == ["bad"])
        #expect(bad.log.isEmpty)
        #expect(good.log == ["start", "stop"])
    }

    @Test func collectsMenuItemsInRegistrationOrder() {
        let registry = ModuleRegistry()
        registry.register(FakeModule(id: "a", items: [NSMenuItem(title: "A1", action: nil, keyEquivalent: "")]))
        registry.register(FakeModule(id: "b", items: [NSMenuItem(title: "B1", action: nil, keyEquivalent: "")]))

        #expect(registry.menuItems.map(\.title) == ["A1", "B1"])
    }

    @Test func separatorFollowsEachModuleThatHasMenuItems() {
        let registry = ModuleRegistry()
        registry.register(FakeModule(id: "a", items: [NSMenuItem(title: "A1", action: nil, keyEquivalent: "")]))
        registry.register(FakeModule(id: "empty"))
        registry.register(FakeModule(id: "c", items: [
            NSMenuItem(title: "C1", action: nil, keyEquivalent: ""),
            NSMenuItem(title: "C2", action: nil, keyEquivalent: ""),
        ]))

        let described = registry.menuItemsWithSeparators.map { $0.isSeparatorItem ? "---" : $0.title }

        #expect(described == ["A1", "---", "C1", "C2", "---"])
    }

    @Test func noModulesMeansNoSeparators() {
        #expect(ModuleRegistry().menuItemsWithSeparators.isEmpty)
    }

    @Test func menuOpenAndCloseAreForwardedToStartedModulesOnly() {
        let registry = ModuleRegistry()
        let bad = FakeModule(id: "bad")
        bad.shouldFail = true
        let good = FakeModule(id: "good")
        registry.register(bad)
        registry.register(good)
        registry.startAll()

        registry.menuWillOpen()
        registry.menuDidClose()

        #expect(good.log == ["start", "menuWillOpen", "menuDidClose"])
        #expect(bad.log.isEmpty)
    }

    @Test func menuCallbacksAreNotForwardedAfterStopAll() {
        let registry = ModuleRegistry()
        let module = FakeModule(id: "m")
        registry.register(module)
        registry.startAll()
        registry.stopAll()

        registry.menuWillOpen()

        #expect(module.log == ["start", "stop"])
    }

    @Test func menuCallbacksHaveDefaultNoOpImplementations() {
        @MainActor final class Bare: AppModule {
            let id = "bare"
            let name = "bare"
            func start() throws {}
            func stop() {}
        }
        let bare = Bare()
        bare.menuWillOpen()
        bare.menuDidClose()
        #expect(bare.menuItems.isEmpty)
    }

    @Test func defaultMenuItemsAndSettingsViewAreEmpty() {
        @MainActor final class Bare: AppModule {
            let id = "bare"
            let name = "bare"
            func start() throws {}
            func stop() {}
        }
        let bare = Bare()
        #expect(bare.menuItems.isEmpty)
        #expect(bare.settingsView == nil)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh --filter ModuleRegistryTests`
Expected: 编译失败，`value of type 'ModuleRegistry' has no member 'menuItemsWithSeparators'`

- [ ] **Step 3: 替换 `Sources/Core/AppModule.swift`**

```swift
import AppKit
import SwiftUI

/// MyKit 的一个功能模块（剪切板、截图、系统监控……）。外壳只通过这个协议认识模块。
@MainActor
public protocol AppModule: AnyObject {
    var id: String { get }
    /// 显示在偏好设置里的中文名
    var name: String { get }
    func start() throws
    func stop()
    /// 放进右上角菜单的菜单项
    var menuItems: [NSMenuItem] { get }
    /// 放进偏好设置窗口的设置页
    var settingsView: AnyView? { get }
    /// 右上角菜单即将打开（只通知成功启动的模块）
    func menuWillOpen()
    /// 右上角菜单已经关闭
    func menuDidClose()
}

public extension AppModule {
    var menuItems: [NSMenuItem] { [] }
    var settingsView: AnyView? { nil }
    func menuWillOpen() {}
    func menuDidClose() {}
}
```

- [ ] **Step 4: 替换 `Sources/Core/ModuleRegistry.swift`**

```swift
import AppKit

@MainActor
public final class ModuleRegistry {
    public private(set) var modules: [AppModule] = []
    public private(set) var failures: [(id: String, error: Error)] = []
    private var started: [AppModule] = []

    public init() {}

    public func register(_ module: AppModule) {
        modules.append(module)
    }

    /// 逐个启动；某个模块启动失败只记录，不影响其他模块。
    public func startAll() {
        for module in modules {
            do {
                try module.start()
                started.append(module)
            } catch {
                failures.append((id: module.id, error: error))
            }
        }
    }

    /// 只停止成功启动过的模块，顺序与启动相反。
    public func stopAll() {
        for module in started.reversed() {
            module.stop()
        }
        started.removeAll()
    }

    public var menuItems: [NSMenuItem] {
        modules.flatMap(\.menuItems)
    }

    /// 右上角菜单用：按注册顺序排列，每个模块的菜单项后面跟一条分隔线；没有菜单项的模块不占位置。
    public var menuItemsWithSeparators: [NSMenuItem] {
        modules.flatMap { module -> [NSMenuItem] in
            let items = module.menuItems
            return items.isEmpty ? [] : items + [NSMenuItem.separator()]
        }
    }

    /// 右上角菜单即将打开：通知所有成功启动的模块。
    public func menuWillOpen() {
        for module in started {
            module.menuWillOpen()
        }
    }

    public func menuDidClose() {
        for module in started {
            module.menuDidClose()
        }
    }
}
```

- [ ] **Step 5: 替换 `Sources/MyKit/StatusBarController.swift`**

```swift
import AppKit

/// 屏幕右上角的 MyKit 图标（以及图标右边可选的一段文字）。
/// 给 NSStatusItem 设置 menu 后，系统对左键和右键都会弹出同一个菜单。
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    enum IconState { case normal, paused, warning }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onOpenSettings: () -> Void
    private let onMenuWillOpen: () -> Void
    private let onMenuDidClose: () -> Void

    /// moduleMenuItems：各模块的菜单项，已经带好分隔线（见 ModuleRegistry.menuItemsWithSeparators）。
    init(
        moduleMenuItems: [NSMenuItem],
        onOpenSettings: @escaping () -> Void,
        onMenuWillOpen: @escaping () -> Void = {},
        onMenuDidClose: @escaping () -> Void = {}
    ) {
        self.onOpenSettings = onOpenSettings
        self.onMenuWillOpen = onMenuWillOpen
        self.onMenuDidClose = onMenuDidClose
        super.init()

        let menu = NSMenu()
        for moduleItem in moduleMenuItems {
            menu.addItem(moduleItem)
        }
        let settings = NSMenuItem(title: "偏好设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 MyKit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self

        item.menu = menu
        setIcon(.normal)
    }

    func setIcon(_ state: IconState) {
        let symbol = state == .warning ? "exclamationmark.triangle" : "square.stack.3d.up"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MyKit")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.appearsDisabled = (state == .paused)
    }

    /// 图标右边的文字（系统监控的 "CPU 12%  内存 63%"）。传 nil 则只显示图标。
    func setTitle(_ title: NSAttributedString?) {
        guard let button = item.button else { return }
        if let title, title.length > 0 {
            button.attributedTitle = title
            button.imagePosition = .imageLeft
        } else {
            button.attributedTitle = NSAttributedString()
            button.imagePosition = .imageOnly
        }
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        onMenuWillOpen()
    }

    func menuDidClose(_ menu: NSMenu) {
        onMenuDidClose()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }
}
```

- [ ] **Step 6: 替换 `Sources/MyKit/AppDelegate.swift`（只改了创建 StatusBarController 的那一段）**

```swift
import AppKit
import ClipboardModule
import Core
import ScreenshotModule
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.imiros.mykit", category: "app")
    private let registry = ModuleRegistry()
    private let eventTap = GlobalKeyTap()
    private let hotkeys = HotkeySettings()
    private var hotkeyObservers: [NSObjectProtocol] = []
    private let accessibilityWatcher = AccessibilityWatcher()
    private let onboarding = OnboardingWindowController()
    private var clipboard: ClipboardModule?
    private var screenshot: ScreenshotModule?
    private var statusBar: StatusBarController?
    private var settingsWindow: SettingsWindowController?
    private var eventTapFailed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let clipboard = try ClipboardModule(databaseURL: ClipboardModule.defaultDatabaseURL)
            clipboard.onPausedChange = { [weak self] _ in self?.refreshIcon() }
            registry.register(clipboard)
            self.clipboard = clipboard
        } catch {
            log.error("剪切板模块初始化失败: \(String(describing: error), privacy: .public)")
        }

        let screenshot = ScreenshotModule()
        registry.register(screenshot)
        self.screenshot = screenshot

        registry.startAll()
        for failure in registry.failures {
            log.error("模块 \(failure.id, privacy: .public) 启动失败: \(String(describing: failure.error), privacy: .public)")
        }

        let settingsWindow = SettingsWindowController(modules: registry.modules)
        self.settingsWindow = settingsWindow
        statusBar = StatusBarController(
            moduleMenuItems: registry.menuItemsWithSeparators,
            onOpenSettings: { settingsWindow.show() },
            onMenuWillOpen: { [weak self] in self?.registry.menuWillOpen() },
            onMenuDidClose: { [weak self] in self?.registry.menuDidClose() }
        )

        eventTap.onDoubleTap = { [weak self] in
            self?.clipboard?.togglePanel()
        }
        applyHotkeys()
        observeHotkeySettings()
        accessibilityWatcher.onChange = { [weak self] trusted in
            self?.accessibilityChanged(trusted)
        }
        accessibilityWatcher.start()
        accessibilityChanged(accessibilityWatcher.isTrusted)

        log.info("MyKit 已启动，辅助功能授权=\(self.accessibilityWatcher.isTrusted), 剪切板需用户批准=\(Permissions.pasteboardNeedsUserApproval)")

        if clipboard?.recoveredFromCorruption == true {
            showDatabaseRecoveredAlert()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap.stop()
        accessibilityWatcher.stop()
        registry.stopAll()
    }

    /// 按当前设置（重新）注册快捷键。用户在偏好设置里改完立即调用，无需重启。
    private func applyHotkeys() {
        eventTap.unregisterAll()
        eventTap.doubleTapModifier = hotkeys.clipboardDoubleTap
        eventTap.register(hotkeys.screenshotCombo) { [weak self] in
            self?.screenshot?.startCapture()
        }
    }

    private func observeHotkeySettings() {
        let center = NotificationCenter.default
        hotkeyObservers = [
            center.addObserver(forName: HotkeySettings.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyHotkeys() }
            },
            // 设置页录制新快捷键期间暂停全局监听，否则现有快捷键会被吞掉、录不进去
            center.addObserver(forName: HotkeySettings.recordingDidBeginNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.eventTap.isSuspended = true }
            },
            center.addObserver(forName: HotkeySettings.recordingDidEndNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.eventTap.isSuspended = false }
            },
        ]
    }

    /// 授权状态变化（含启动时的首次检查）：有权限就开始监听双击 Option，没有就弹引导。
    private func accessibilityChanged(_ trusted: Bool) {
        if trusted {
            eventTapFailed = !eventTap.start()
            onboarding.close()
        } else {
            eventTap.stop()
            eventTapFailed = false
            onboarding.show()
        }
        refreshIcon()
    }

    private func refreshIcon() {
        if !accessibilityWatcher.isTrusted || eventTapFailed {
            statusBar?.setIcon(.warning)
        } else if clipboard?.isPaused == true {
            statusBar?.setIcon(.paused)
        } else {
            statusBar?.setIcon(.normal)
        }
    }

    private func showDatabaseRecoveredAlert() {
        let alert = NSAlert()
        alert.messageText = "剪切板历史已重建"
        alert.informativeText = "原来的历史数据库已损坏，MyKit 已将它备份并新建了一个空的历史。备份文件在 ~/Library/Application Support/MyKit/ 里。"
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
```

- [ ] **Step 7: 运行全部测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 311 tests`，零警告。

- [ ] **Step 8: Commit**

```bash
git add Sources/Core/AppModule.swift Sources/Core/ModuleRegistry.swift Sources/MyKit Tests/CoreTests/ModuleRegistryTests.swift
git commit -m "feat(shell): menu open/close hooks for modules, status item title, separator after each module's menu items"
```

---

### Task 2: SystemMonitorModule Target + 纯计算

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SystemMonitorModule/CPULoad.swift`, `Sources/SystemMonitorModule/MemoryUsage.swift`, `Sources/SystemMonitorModule/ProcessGrouping.swift`, `Sources/SystemMonitorModule/TopProcesses.swift`, `Sources/SystemMonitorModule/MonitorFormat.swift`, `Sources/SystemMonitorModule/MonitorSettings.swift`
- Test: `Tests/SystemMonitorModuleTests/CPULoadTests.swift`, `Tests/SystemMonitorModuleTests/MemoryUsageTests.swift`, `Tests/SystemMonitorModuleTests/ProcessGroupingTests.swift`, `Tests/SystemMonitorModuleTests/TopProcessesTests.swift`, `Tests/SystemMonitorModuleTests/MonitorFormatTests.swift`, `Tests/SystemMonitorModuleTests/MonitorSettingsTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `CoreTicks(user:system:idle:nice:)`（均为 `UInt32`）、`CPUTicks(cores:)`、`CPULoad { user, system, total }`（0…100）、`CPULoad.between(_ earlier: CPUTicks, _ later: CPUTicks) -> CPULoad?`
  - `MemoryUsage(usedBytes:totalBytes:)`、`.percent`、`MemoryUsage.from(internalPages:purgeablePages:wiredPages:compressedPages:pageSize:totalBytes:)`
  - `AppGroup(key:fallbackName:bundlePath:)`（`Hashable`）、`ProcessGrouping.group(forPath:) -> AppGroup?`
  - `ProcessSample(pid: Int32, cpuNanoseconds: UInt64, footprintBytes: UInt64, path: String)`、`TopEntry(group:value:)`、`TopProcesses.limit == 5`、`TopProcesses.byCPU(earlier:later:intervalNanoseconds:) -> [TopEntry]`、`TopProcesses.byMemory(_:) -> [TopEntry]`
  - `MonitorFormat.percent(_: Double?) -> String`、`.percentOneDecimal(_:)`、`.bytes(_: UInt64)`、`.memorySummary(usedBytes:totalBytes:)`、`.isWarning(_: Double?)`、`.titleSegments(cpu:memory:) -> [TitleSegment]`（`TitleSegment { text, isWarning }`）
  - `MonitorSettings(defaults:)`：`showInMenuBar`（默认 true）、`interval`（1 / 2 / 5，默认 2）、`notifyChanged()`、`didChangeNotification`（object = 对应的 UserDefaults）、`showInMenuBarKey`、`intervalKey`、`allowedIntervals`、`defaultInterval`

计算规则见设计文档 §3。两点细化：告警线按**显示出来的整数**判断（84.5% 显示为 85%，所以也标红）；CPU 榜除了"CPU 时间没有变小"之外，还要求同一个 pid 两次采样的路径相同（路径变了同样说明 pid 被复用）。

- [ ] **Step 1: 更新 `Package.swift`（完整内容）**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyKit",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Core"),
        .target(
            name: "ClipboardModule",
            dependencies: ["Core"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "ScreenshotModule", dependencies: ["Core"]),
        .target(name: "SystemMonitorModule", dependencies: ["Core"]),
        .executableTarget(name: "MyKit", dependencies: ["Core", "ClipboardModule", "ScreenshotModule"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "ClipboardModuleTests", dependencies: ["ClipboardModule"]),
        .testTarget(name: "ScreenshotModuleTests", dependencies: ["ScreenshotModule"]),
        .testTarget(name: "SystemMonitorModuleTests", dependencies: ["SystemMonitorModule"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: 写六个失败的测试文件**

`Tests/SystemMonitorModuleTests/CPULoadTests.swift`:

```swift
import Testing
@testable import SystemMonitorModule

@Suite struct CPULoadTests {
    private func ticks(_ cores: [(UInt32, UInt32, UInt32, UInt32)]) -> CPUTicks {
        CPUTicks(cores: cores.map { CoreTicks(user: $0.0, system: $0.1, idle: $0.2, nice: $0.3) })
    }

    @Test func computesUserAndSystemShareAcrossAllCores() throws {
        let earlier = ticks([(100, 50, 850, 0), (200, 100, 700, 0)])
        let later = ticks([(130, 60, 910, 0), (210, 110, 780, 0)])     // Δ：用户 40，系统 20，空闲 140 → 共 200

        let load = try #require(CPULoad.between(earlier, later))

        #expect(load.user == 20)
        #expect(load.system == 10)
        #expect(load.total == 30)
    }

    @Test func niceCountsAsUser() throws {
        let load = try #require(CPULoad.between(ticks([(0, 0, 0, 0)]), ticks([(10, 0, 80, 10)])))
        #expect(load.user == 20)
        #expect(load.system == 0)
    }

    @Test func survivesThirtyTwoBitCounterWraparound() throws {
        let nearMax = UInt32.max - 9
        let earlier = ticks([(nearMax, 0, nearMax, 0)])
        let later = ticks([(40, 0, 40, 0)])                             // 两个计数器都绕回去了，各走了 50

        let load = try #require(CPULoad.between(earlier, later))

        #expect(load.user == 50)
        #expect(load.system == 0)
    }

    @Test func returnsNilWhenCoreCountChanges() {
        #expect(CPULoad.between(ticks([(1, 1, 1, 0)]), ticks([(2, 2, 2, 0), (1, 1, 1, 0)])) == nil)
    }

    @Test func returnsNilWhenNothingTickedOrNoCores() {
        let same = ticks([(5, 5, 5, 5)])
        #expect(CPULoad.between(same, same) == nil)
        #expect(CPULoad.between(ticks([]), ticks([])) == nil)
    }

    @Test func fullyBusyIsOneHundredPercent() throws {
        let load = try #require(CPULoad.between(ticks([(0, 0, 0, 0)]), ticks([(70, 30, 0, 0)])))
        #expect(load.total == 100)
    }
}
```

`Tests/SystemMonitorModuleTests/MemoryUsageTests.swift`:

```swift
import Testing
@testable import SystemMonitorModule

@Suite struct MemoryUsageTests {
    private let gigabyte: UInt64 = 1_073_741_824

    @Test func usedIsAppMemoryPlusWiredPlusCompressed() {
        // 页大小 16 KB；internal 500 − purgeable 100 = 400，加 wired 200、compressed 50 → 650 页
        let usage = MemoryUsage.from(
            internalPages: 500, purgeablePages: 100, wiredPages: 200, compressedPages: 50,
            pageSize: 16_384, totalBytes: 16 * gigabyte)

        #expect(usage.usedBytes == 10_649_600)      // 650 × 16384
        #expect(usage.totalBytes == 16 * gigabyte)
    }

    @Test func purgeableLargerThanInternalCountsAsZeroAppMemory() {
        let usage = MemoryUsage.from(
            internalPages: 10, purgeablePages: 30, wiredPages: 5, compressedPages: 5,
            pageSize: 4096, totalBytes: gigabyte)
        #expect(usage.usedBytes == 40_960)          // 只剩 wired + compressed = 10 页
    }

    @Test func percentIsUsedOverTotalClampedToOneHundred() {
        #expect(MemoryUsage(usedBytes: 4 * gigabyte, totalBytes: 16 * gigabyte).percent == 25)
        #expect(MemoryUsage(usedBytes: 20 * gigabyte, totalBytes: 16 * gigabyte).percent == 100)
        #expect(MemoryUsage(usedBytes: 1, totalBytes: 0).percent == 0)
    }
}
```

`Tests/SystemMonitorModuleTests/ProcessGroupingTests.swift`:

```swift
import Testing
@testable import SystemMonitorModule

@Suite struct ProcessGroupingTests {
    @Test func processInsideAnAppBelongsToThatApp() {
        let group = ProcessGrouping.group(forPath: "/Applications/WeChat.app/Contents/MacOS/WeChat")
        #expect(group == AppGroup(key: "/Applications/WeChat.app", fallbackName: "WeChat", bundlePath: "/Applications/WeChat.app"))
    }

    @Test func helperInsideNestedAppBelongsToTheOutermostApp() {
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/129/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        let group = ProcessGrouping.group(forPath: helper)
        #expect(group?.key == "/Applications/Google Chrome.app")
        #expect(group?.fallbackName == "Google Chrome")
        #expect(group?.bundlePath == "/Applications/Google Chrome.app")
    }

    @Test func helperAndMainProcessShareOneGroup() {
        let main = ProcessGrouping.group(forPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        let helper = ProcessGrouping.group(forPath: "/Applications/Google Chrome.app/Contents/Frameworks/X.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper")
        #expect(main == helper)
    }

    @Test func processOutsideAnyAppIsGroupedByExecutableName() {
        let group = ProcessGrouping.group(forPath: "/usr/local/bin/node")
        #expect(group == AppGroup(key: "node", fallbackName: "node", bundlePath: nil))
    }

    @Test func sameExecutableNameInDifferentFoldersIsOneGroup() {
        #expect(ProcessGrouping.group(forPath: "/opt/a/java") == ProcessGrouping.group(forPath: "/opt/b/java"))
    }

    @Test func emptyPathHasNoGroup() {
        #expect(ProcessGrouping.group(forPath: "") == nil)
    }
}
```

`Tests/SystemMonitorModuleTests/TopProcessesTests.swift`:

```swift
import Testing
@testable import SystemMonitorModule

@Suite struct TopProcessesTests {
    private let second: UInt64 = 1_000_000_000
    private let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    private let chromeHelper = "/Applications/Google Chrome.app/Contents/Frameworks/F.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
    private let wechat = "/Applications/WeChat.app/Contents/MacOS/WeChat"

    private func sample(_ pid: Int32, cpuMilliseconds: UInt64, megabytes: UInt64 = 10, path: String) -> ProcessSample {
        ProcessSample(pid: pid, cpuNanoseconds: cpuMilliseconds * 1_000_000, footprintBytes: megabytes * 1_048_576, path: path)
    }

    @Test func cpuIsSummedPerAppAndExpressedPerCore() {
        let earlier = [sample(1, cpuMilliseconds: 1000, path: chrome), sample(2, cpuMilliseconds: 500, path: chromeHelper), sample(3, cpuMilliseconds: 0, path: wechat)]
        let later = [sample(1, cpuMilliseconds: 1300, path: chrome), sample(2, cpuMilliseconds: 1400, path: chromeHelper), sample(3, cpuMilliseconds: 100, path: wechat)]

        let top = TopProcesses.byCPU(earlier: earlier, later: later, intervalNanoseconds: 2 * second)

        #expect(top.map(\.group.fallbackName) == ["Google Chrome", "WeChat"])
        #expect(top[0].value == 60)      // (300 + 900) 毫秒 / 2 秒
        #expect(top[1].value == 5)
    }

    @Test func aBusyMultiThreadedAppCanExceedOneHundredPercent() {
        let top = TopProcesses.byCPU(
            earlier: [sample(1, cpuMilliseconds: 0, path: chrome)],
            later: [sample(1, cpuMilliseconds: 2500, path: chrome)],
            intervalNanoseconds: second)
        #expect(top.first?.value == 250)
    }

    @Test func ignoresNewProcessesAndReusedPids() {
        let earlier = [sample(1, cpuMilliseconds: 5000, path: chrome), sample(2, cpuMilliseconds: 100, path: wechat)]
        let later = [
            sample(1, cpuMilliseconds: 200, path: chrome),          // CPU 时间变小：pid 被复用了
            sample(2, cpuMilliseconds: 900, path: "/usr/bin/yes"),  // 同一个 pid 换了程序
            sample(9, cpuMilliseconds: 800, path: wechat),          // 第一次采样时还不存在
        ]
        #expect(TopProcesses.byCPU(earlier: earlier, later: later, intervalNanoseconds: second).isEmpty)
    }

    @Test func dropsEntriesBelowOneTenthOfAPercentAndKeepsTopFive() {
        var earlier: [ProcessSample] = []
        var later: [ProcessSample] = []
        for index in 1...7 {
            let path = "/opt/tools/tool\(index)"
            earlier.append(sample(Int32(index), cpuMilliseconds: 0, path: path))
            later.append(sample(Int32(index), cpuMilliseconds: UInt64(index) * 10, path: path))
        }
        earlier.append(sample(100, cpuMilliseconds: 0, path: "/opt/tools/idle"))
        later.append(sample(100, cpuMilliseconds: 0, path: "/opt/tools/idle"))

        let top = TopProcesses.byCPU(earlier: earlier, later: later, intervalNanoseconds: second)

        #expect(top.map(\.group.fallbackName) == ["tool7", "tool6", "tool5", "tool4", "tool3"])
    }

    @Test func zeroIntervalGivesNoCPURanking() {
        let samples = [sample(1, cpuMilliseconds: 10, path: chrome)]
        #expect(TopProcesses.byCPU(earlier: samples, later: samples, intervalNanoseconds: 0).isEmpty)
    }

    @Test func memoryIsSummedPerAppLargestFirst() {
        let samples = [
            sample(1, cpuMilliseconds: 0, megabytes: 300, path: chrome),
            sample(2, cpuMilliseconds: 0, megabytes: 500, path: chromeHelper),
            sample(3, cpuMilliseconds: 0, megabytes: 900, path: wechat),
            sample(4, cpuMilliseconds: 0, megabytes: 50, path: ""),          // 读不到路径的进程不参与
        ]

        let top = TopProcesses.byMemory(samples)

        #expect(top.map(\.group.fallbackName) == ["WeChat", "Google Chrome"])
        #expect(top[0].value == 943_718_400)     // 900 MB
        #expect(top[1].value == 838_860_800)     // 800 MB
    }

    @Test func equalValuesAreOrderedByNameSoTheListDoesNotFlicker() {
        let samples = [
            sample(1, cpuMilliseconds: 0, megabytes: 100, path: "/opt/zeta"),
            sample(2, cpuMilliseconds: 0, megabytes: 100, path: "/opt/alpha"),
            sample(3, cpuMilliseconds: 0, megabytes: 100, path: "/opt/mid"),
        ]
        #expect(TopProcesses.byMemory(samples).map(\.group.fallbackName) == ["alpha", "mid", "zeta"])
    }

    @Test func memoryRankingKeepsOnlyTopFive() {
        let samples = (1...8).map { sample(Int32($0), cpuMilliseconds: 0, megabytes: UInt64($0) * 10, path: "/opt/p\($0)") }
        #expect(TopProcesses.byMemory(samples).map(\.group.fallbackName) == ["p8", "p7", "p6", "p5", "p4"])
    }
}
```

`Tests/SystemMonitorModuleTests/MonitorFormatTests.swift`:

```swift
import Testing
@testable import SystemMonitorModule

@Suite struct MonitorFormatTests {
    private let gigabyte: UInt64 = 1_073_741_824
    private let megabyte: UInt64 = 1_048_576

    @Test func totalPercentIsRoundedAndClamped() {
        #expect(MonitorFormat.percent(12.4) == "12%")
        #expect(MonitorFormat.percent(12.5) == "13%")
        #expect(MonitorFormat.percent(0) == "0%")
        #expect(MonitorFormat.percent(130) == "100%")
        #expect(MonitorFormat.percent(-3) == "0%")
    }

    @Test func missingValueShowsDashes() {
        #expect(MonitorFormat.percent(nil) == "--")
        #expect(MonitorFormat.percent(Double.nan) == "--")
    }

    @Test func perAppPercentKeepsOneDecimalAndMayExceedOneHundred() {
        #expect(MonitorFormat.percentOneDecimal(28.44) == "28.4%")
        #expect(MonitorFormat.percentOneDecimal(250) == "250.0%")
        #expect(MonitorFormat.percentOneDecimal(0.1) == "0.1%")
    }

    @Test func bytesUseGigabytesFromOneGigabyteUp() {
        let threePointTwo = 3 * gigabyte + 205 * megabyte
        #expect(MonitorFormat.bytes(threePointTwo) == "3.2 GB")
        #expect(MonitorFormat.bytes(gigabyte) == "1.0 GB")
        #expect(MonitorFormat.bytes(850 * megabyte) == "850 MB")
        #expect(MonitorFormat.bytes(0) == "0 MB")
    }

    @Test func memorySummaryShowsUsedOverTotal() {
        let used = 10 * gigabyte + 103 * megabyte
        #expect(MonitorFormat.memorySummary(usedBytes: used, totalBytes: 16 * gigabyte) == "10.1 / 16 GB")
        let oddTotal = 18 * gigabyte + 512 * megabyte
        #expect(MonitorFormat.memorySummary(usedBytes: gigabyte, totalBytes: oddTotal) == "1.0 / 18.5 GB")
    }

    @Test func warningStartsAtEightyFiveAsDisplayed() {
        #expect(!MonitorFormat.isWarning(84.4))
        #expect(MonitorFormat.isWarning(84.5))       // 显示为 85%，所以也标红
        #expect(MonitorFormat.isWarning(85))
        #expect(MonitorFormat.isWarning(100))
        #expect(!MonitorFormat.isWarning(nil))
    }

    @Test func titleIsFourSegmentsAndOnlyNumbersCanWarn() {
        let segments = MonitorFormat.titleSegments(cpu: 12, memory: 91)

        #expect(segments.map(\.text) == ["CPU ", "12%", "  内存 ", "91%"])
        #expect(segments.map(\.isWarning) == [false, false, false, true])
        #expect(segments.map(\.text).joined() == "CPU 12%  内存 91%")
    }

    @Test func titleBeforeFirstCPUReadingShowsDashes() {
        let text = MonitorFormat.titleSegments(cpu: nil, memory: 63).map(\.text).joined()
        #expect(text == "CPU --  内存 63%")
    }
}
```

`Tests/SystemMonitorModuleTests/MonitorSettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import SystemMonitorModule

@Suite struct MonitorSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsAreShowInMenuBarEveryTwoSeconds() {
        let settings = MonitorSettings(defaults: makeDefaults())
        #expect(settings.showInMenuBar)
        #expect(settings.interval == 2)
    }

    @Test func valuesRoundTrip() {
        let defaults = makeDefaults()
        MonitorSettings(defaults: defaults).showInMenuBar = false
        MonitorSettings(defaults: defaults).interval = 5

        #expect(!MonitorSettings(defaults: defaults).showInMenuBar)
        #expect(MonitorSettings(defaults: defaults).interval == 5)
    }

    @Test func unsupportedIntervalFallsBackToTwo() {
        let defaults = makeDefaults()
        defaults.set(3, forKey: MonitorSettings.intervalKey)
        #expect(MonitorSettings(defaults: defaults).interval == 2)
        defaults.set(-1, forKey: MonitorSettings.intervalKey)
        #expect(MonitorSettings(defaults: defaults).interval == 2)
    }

    @Test func changesPostNotificationForThatDefaults() {
        let defaults = makeDefaults()
        var count = 0
        let token = NotificationCenter.default.addObserver(
            forName: MonitorSettings.didChangeNotification, object: defaults, queue: nil
        ) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        MonitorSettings(defaults: defaults).showInMenuBar = false
        MonitorSettings(defaults: defaults).interval = 1
        MonitorSettings(defaults: defaults).notifyChanged()

        #expect(count == 3)
    }
}
```

- [ ] **Step 3: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败（`SystemMonitorModule` 还没有源文件 / `cannot find 'CPULoad' in scope`）

- [ ] **Step 4: 写 `Sources/SystemMonitorModule/CPULoad.swift`**

```swift
import Foundation

/// 一个核心自开机以来的累计 tick。内核给的是 32 位无符号数，跑久了会回绕。
public struct CoreTicks: Equatable, Sendable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// 某一时刻所有核心的 tick 快照。
public struct CPUTicks: Equatable, Sendable {
    public var cores: [CoreTicks]

    public init(cores: [CoreTicks]) {
        self.cores = cores
    }
}

/// 两份快照之间的 CPU 占用（占全部核心的百分比，0…100）。
public struct CPULoad: Equatable, Sendable {
    /// 用户态（含 nice）
    public let user: Double
    /// 内核态
    public let system: Double

    public var total: Double { user + system }

    public init(user: Double, system: Double) {
        self.user = user
        self.system = system
    }

    /// 核心数对不上、或两次采样之间没有任何 tick（采样太近）时返回 nil。
    public static func between(_ earlier: CPUTicks, _ later: CPUTicks) -> CPULoad? {
        guard !later.cores.isEmpty, earlier.cores.count == later.cores.count else { return nil }
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        for (before, after) in zip(earlier.cores, later.cores) {
            // &- 是回绕减法：计数器从 UInt32.max 绕回 0 之后差值依然正确
            user += UInt64(after.user &- before.user) + UInt64(after.nice &- before.nice)
            system += UInt64(after.system &- before.system)
            idle += UInt64(after.idle &- before.idle)
        }
        let total = user + system + idle
        guard total > 0 else { return nil }
        return CPULoad(
            user: Double(user) / Double(total) * 100,
            system: Double(system) / Double(total) * 100
        )
    }
}
```

- [ ] **Step 5: 写 `Sources/SystemMonitorModule/MemoryUsage.swift`**

```swift
import Foundation

public struct MemoryUsage: Equatable, Sendable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64

    public init(usedBytes: UInt64, totalBytes: UInt64) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }

    /// 0…100
    public var percent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes) * 100, 0), 100)
    }

    /// 与"活动监视器"的"已使用内存"同一口径：App 内存（internal − purgeable）+ 联动内存 + 被压缩的内存。
    public static func from(
        internalPages: UInt64,
        purgeablePages: UInt64,
        wiredPages: UInt64,
        compressedPages: UInt64,
        pageSize: UInt64,
        totalBytes: UInt64
    ) -> MemoryUsage {
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let used = (appPages + wiredPages + compressedPages) * pageSize
        return MemoryUsage(usedBytes: used, totalBytes: totalBytes)
    }
}
```

- [ ] **Step 6: 写 `Sources/SystemMonitorModule/ProcessGrouping.swift`**

```swift
import Foundation

/// 排行榜里的一项"软件"：同一个 .app 里的所有进程（含辅助进程）算作一组。
public struct AppGroup: Hashable, Sendable {
    /// 分组键：.app 包的路径，或者（不在 .app 里的进程）可执行文件名
    public let key: String
    /// 取不到本地化显示名时用的名字
    public let fallbackName: String
    /// .app 包的路径；不在 .app 里的进程为 nil
    public let bundlePath: String?

    public init(key: String, fallbackName: String, bundlePath: String?) {
        self.key = key
        self.fallbackName = fallbackName
        self.bundlePath = bundlePath
    }
}

public enum ProcessGrouping {
    /// 可执行文件路径 → 所属的软件。路径为空返回 nil。
    /// 路径里有 `.app/` 就取**最外层**的 .app（Chrome 的几十个 Helper 都在 Google Chrome.app 里面）。
    public static func group(forPath path: String) -> AppGroup? {
        guard !path.isEmpty else { return nil }
        if let range = path.range(of: ".app/") {
            let bundlePath = String(path[..<range.lowerBound]) + ".app"
            let fileName = (bundlePath as NSString).lastPathComponent
            let name = String(fileName.dropLast(4))
            return AppGroup(key: bundlePath, fallbackName: name.isEmpty ? fileName : name, bundlePath: bundlePath)
        }
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty else { return nil }
        return AppGroup(key: name, fallbackName: name, bundlePath: nil)
    }
}
```

- [ ] **Step 7: 写 `Sources/SystemMonitorModule/TopProcesses.swift`**

```swift
import Foundation

/// 一个进程在某一时刻的采样。
public struct ProcessSample: Equatable, Sendable {
    public let pid: Int32
    /// 自进程启动以来累计用掉的 CPU 时间（用户态 + 内核态），纳秒
    public let cpuNanoseconds: UInt64
    /// 内存占用（footprint），与"活动监视器"的"内存"一列同一口径
    public let footprintBytes: UInt64
    /// 可执行文件路径
    public let path: String

    public init(pid: Int32, cpuNanoseconds: UInt64, footprintBytes: UInt64, path: String) {
        self.pid = pid
        self.cpuNanoseconds = cpuNanoseconds
        self.footprintBytes = footprintBytes
        self.path = path
    }
}

/// 排行榜的一行。
public struct TopEntry: Equatable, Sendable, Identifiable {
    public let group: AppGroup
    /// CPU 榜：百分比（按单个核心计，可以超过 100）；内存榜：字节数
    public let value: Double

    public var id: String { group.key }

    public init(group: AppGroup, value: Double) {
        self.group = group
        self.value = value
    }
}

public enum TopProcesses {
    public static let limit = 5
    /// CPU 榜里小于这个百分比的项不显示
    public static let minimumCPUPercent = 0.1

    /// 两份采样 → CPU 榜。与"活动监视器"一致：一个软件占满一个核心 = 100%。
    /// 只统计两次采样里都在、路径没变、CPU 时间没有变小的 pid（否则说明 pid 被系统回收复用了）。
    public static func byCPU(earlier: [ProcessSample], later: [ProcessSample], intervalNanoseconds: UInt64) -> [TopEntry] {
        guard intervalNanoseconds > 0 else { return [] }
        let before = Dictionary(earlier.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var totals: [AppGroup: Double] = [:]
        for sample in later {
            guard let previous = before[sample.pid],
                  previous.path == sample.path,
                  sample.cpuNanoseconds >= previous.cpuNanoseconds,
                  let group = ProcessGrouping.group(forPath: sample.path)
            else { continue }
            let used = Double(sample.cpuNanoseconds - previous.cpuNanoseconds)
            totals[group, default: 0] += used / Double(intervalNanoseconds) * 100
        }
        return ranked(totals.filter { $0.value >= minimumCPUPercent })
    }

    /// 一份采样 → 内存榜。
    public static func byMemory(_ samples: [ProcessSample]) -> [TopEntry] {
        var totals: [AppGroup: Double] = [:]
        for sample in samples {
            guard let group = ProcessGrouping.group(forPath: sample.path) else { continue }
            totals[group, default: 0] += Double(sample.footprintBytes)
        }
        return ranked(totals.filter { $0.value > 0 })
    }

    /// 数值从大到小；数值相同按名字、再按键排序，保证每次刷新顺序稳定。
    private static func ranked(_ totals: [AppGroup: Double]) -> [TopEntry] {
        totals
            .map { TopEntry(group: $0.key, value: $0.value) }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                if lhs.group.fallbackName != rhs.group.fallbackName { return lhs.group.fallbackName < rhs.group.fallbackName }
                return lhs.group.key < rhs.group.key
            }
            .prefix(limit)
            .map { $0 }
    }
}
```

- [ ] **Step 8: 写 `Sources/SystemMonitorModule/MonitorFormat.swift`**

```swift
import Foundation

/// 监控数字的显示格式。纯函数。
public enum MonitorFormat {
    /// 总占用达到这个百分比（按显示出来的整数算）时标红
    public static let warningThreshold = 85
    private static let gigabyte = 1_073_741_824.0
    private static let megabyte = 1_048_576.0

    /// 总占用：四舍五入成整数，夹在 0…100；nil（还没有数据 / 读取失败）显示 "--"。
    public static func percent(_ value: Double?) -> String {
        guard let rounded = roundedPercent(value) else { return "--" }
        return "\(rounded)%"
    }

    /// 单个软件的 CPU：保留 1 位小数，可以超过 100。
    public static func percentOneDecimal(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    /// ≥ 1 GB 显示 "3.2 GB"，否则 "850 MB"。1 GB = 1024³ 字节。
    public static func bytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= gigabyte {
            return String(format: "%.1f GB", value / gigabyte)
        }
        return "\(Int((value / megabyte).rounded())) MB"
    }

    /// "10.1 / 16 GB"；总量是整数 GB 时不带小数。
    public static func memorySummary(usedBytes: UInt64, totalBytes: UInt64) -> String {
        let used = String(format: "%.1f", Double(usedBytes) / gigabyte)
        let totalValue = Double(totalBytes) / gigabyte
        let total = totalValue == totalValue.rounded() ? "\(Int(totalValue))" : String(format: "%.1f", totalValue)
        return "\(used) / \(total) GB"
    }

    public static func isWarning(_ value: Double?) -> Bool {
        guard let rounded = roundedPercent(value) else { return false }
        return rounded >= warningThreshold
    }

    /// 菜单栏标题的一段：文字 + 是否标红。
    public struct TitleSegment: Equatable, Sendable {
        public let text: String
        public let isWarning: Bool

        public init(text: String, isWarning: Bool) {
            self.text = text
            self.isWarning = isWarning
        }
    }

    /// "CPU 12%  内存 63%" 拆成四段，只有数字那两段可能标红。
    public static func titleSegments(cpu: Double?, memory: Double?) -> [TitleSegment] {
        [
            TitleSegment(text: "CPU ", isWarning: false),
            TitleSegment(text: percent(cpu), isWarning: isWarning(cpu)),
            TitleSegment(text: "  内存 ", isWarning: false),
            TitleSegment(text: percent(memory), isWarning: isWarning(memory)),
        ]
    }

    private static func roundedPercent(_ value: Double?) -> Int? {
        guard let value, value.isFinite else { return nil }
        return Int(min(max(value, 0), 100).rounded())
    }
}
```

- [ ] **Step 9: 写 `Sources/SystemMonitorModule/MonitorSettings.swift`**

```swift
import Foundation

public struct MonitorSettings {
    public static let showInMenuBarKey = "monitor.showInMenuBar"
    public static let intervalKey = "monitor.interval"
    public static let allowedIntervals = [1, 2, 5]
    public static let defaultInterval = 2
    /// 设置页改了任何一项之后发出；object = 对应的 UserDefaults
    public static let didChangeNotification = Notification.Name("com.imiros.mykit.monitor.settingsDidChange")

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 是否在菜单栏图标旁边显示 "CPU 12%  内存 63%"。默认显示。
    public var showInMenuBar: Bool {
        get {
            guard defaults.object(forKey: Self.showInMenuBarKey) != nil else { return true }
            return defaults.bool(forKey: Self.showInMenuBarKey)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Self.showInMenuBarKey)
            notifyChanged()
        }
    }

    /// 刷新间隔（秒）：1 / 2 / 5。未设置或存了别的值时为 2。
    public var interval: Int {
        get {
            let stored = defaults.integer(forKey: Self.intervalKey)
            return Self.allowedIntervals.contains(stored) ? stored : Self.defaultInterval
        }
        nonmutating set {
            defaults.set(newValue, forKey: Self.intervalKey)
            notifyChanged()
        }
    }

    /// 设置页用 @AppStorage 直接改了 UserDefaults 之后调用
    public func notifyChanged() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: defaults)
    }
}
```

- [ ] **Step 10: 运行全部测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 346 tests`，零警告。

- [ ] **Step 11: Commit**

```bash
git add Package.swift Sources/SystemMonitorModule Tests/SystemMonitorModuleTests
git commit -m "feat(monitor): module target with CPU load, memory usage, app grouping, top lists, formatting and settings"
```

---

### Task 3: 系统读取器 —— 整机统计与进程采样

**Files:**
- Create: `Sources/SystemMonitorModule/HostStatsReader.swift`, `Sources/SystemMonitorModule/ProcessSampler.swift`
- Test: `Tests/SystemMonitorModuleTests/SystemReadersTests.swift`

**Interfaces:**
- Consumes: `CoreTicks`、`CPUTicks`、`MemoryUsage.from(...)`、`ProcessSample`（Task 2）
- Produces:
  - `protocol HostStatsReading { func cpuTicks() -> CPUTicks?; func memoryUsage() -> MemoryUsage? }`；`struct HostStatsReader: HostStatsReading`
  - `struct ProcessSnapshot { samples: [ProcessSample]; timestampNanoseconds: UInt64 }`（`Equatable`、`Sendable`）
  - `protocol ProcessSampling: Sendable { func sampleAll() -> ProcessSnapshot }`；`struct ProcessSampler: ProcessSampling`

这两个类型只是内核调用的薄包装，接口的用法已经在本机用 `moncheck.swift` 验证过（无需授权；960 个进程里 615 个可读，读不到的是属于 root 的系统进程；采样一遍约 8 毫秒）。三个容易出错的地方已经写进代码注释：`mach_host_self()` 只取一次、`proc_pid_rusage` 的指针要 rebind 成 `rusage_info_t?`、CPU 时间是 mach 时间单位要用 timebase 换算。测试只做冒烟检查。

- [ ] **Step 1: 写失败的测试 `Tests/SystemMonitorModuleTests/SystemReadersTests.swift`**

```swift
import Darwin
import Foundation
import Testing
@testable import SystemMonitorModule

/// 冒烟测试：只确认真的能从内核读到东西、数值在合理范围内，不依赖当前的系统负载。
@Suite struct SystemReadersTests {
    @Test func cpuTicksCoverEveryCore() throws {
        let ticks = try #require(HostStatsReader().cpuTicks())
        #expect(ticks.cores.count == ProcessInfo.processInfo.processorCount)
    }

    @Test func twoCPUReadingsNeverGoBackwardsMoreThanAWrap() throws {
        let reader = HostStatsReader()
        let first = try #require(reader.cpuTicks())
        let second = try #require(reader.cpuTicks())
        #expect(first.cores.count == second.cores.count)
        if let load = CPULoad.between(first, second) {        // 两次读得太近时可能是 nil，也算正常
            #expect(load.total >= 0)
            #expect(load.total <= 100)
        }
    }

    @Test func memoryUsageIsWithinPhysicalMemory() throws {
        let usage = try #require(HostStatsReader().memoryUsage())
        #expect(usage.totalBytes == ProcessInfo.processInfo.physicalMemory)
        #expect(usage.usedBytes > 0)
        #expect(usage.usedBytes <= usage.totalBytes)
    }

    @Test func processSnapshotContainsThisTestProcess() throws {
        let snapshot = ProcessSampler().sampleAll()
        let me = try #require(snapshot.samples.first { $0.pid == getpid() })
        #expect(!me.path.isEmpty)
        #expect(me.footprintBytes > 0)
        #expect(me.cpuNanoseconds > 0)
        #expect(snapshot.timestampNanoseconds > 0)
    }

    @Test func snapshotsAreTakenInTimeOrder() {
        let sampler = ProcessSampler()
        let first = sampler.sampleAll()
        let second = sampler.sampleAll()
        #expect(second.timestampNanoseconds >= first.timestampNanoseconds)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh --filter SystemReadersTests`
Expected: 编译失败，`cannot find 'HostStatsReader' in scope`

- [ ] **Step 3: 写 `Sources/SystemMonitorModule/HostStatsReader.swift`**

```swift
import Darwin
import Foundation

/// 读取整机的 CPU tick 和内存统计。抽成协议是为了在测试里换成假实现。
public protocol HostStatsReading {
    func cpuTicks() -> CPUTicks?
    func memoryUsage() -> MemoryUsage?
}

/// 直接读 macOS 内核接口（"活动监视器"用的也是这些）。无需任何授权，一次调用是微秒级。
public struct HostStatsReader: HostStatsReading {
    /// mach_host_self() 每调一次都会多占一个端口引用，所以整个进程只取一次
    private static let host = mach_host_self()

    public init() {}

    public func cpuTicks() -> CPUTicks? {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(Self.host, PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }
        var cores: [CoreTicks] = []
        cores.reserveCapacity(Int(coreCount))
        for core in 0..<Int(coreCount) {
            let base = core * Int(CPU_STATE_MAX)
            cores.append(CoreTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            ))
        }
        return cores.isEmpty ? nil : CPUTicks(cores: cores)
    }

    public func memoryUsage() -> MemoryUsage? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(Self.host, HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(Self.host, &pageSize) == KERN_SUCCESS, pageSize > 0 else { return nil }
        return MemoryUsage.from(
            internalPages: UInt64(stats.internal_page_count),
            purgeablePages: UInt64(stats.purgeable_count),
            wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count),
            pageSize: UInt64(pageSize),
            totalBytes: ProcessInfo.processInfo.physicalMemory
        )
    }
}
```

- [ ] **Step 4: 写 `Sources/SystemMonitorModule/ProcessSampler.swift`**

```swift
import Darwin
import Foundation

/// 某一时刻全部可读进程的采样。
public struct ProcessSnapshot: Equatable, Sendable {
    public let samples: [ProcessSample]
    /// 单调时钟（纳秒），用来算两次采样之间隔了多久
    public let timestampNanoseconds: UInt64

    public init(samples: [ProcessSample], timestampNanoseconds: UInt64) {
        self.samples = samples
        self.timestampNanoseconds = timestampNanoseconds
    }
}

/// 采样全部进程。会在后台线程调用，所以要求 Sendable。
public protocol ProcessSampling: Sendable {
    func sampleAll() -> ProcessSnapshot
}

/// 直接读内核接口，无需授权。属于 root 的系统进程（WindowServer、kernel_task 等）读不到，会被跳过；
/// 用户自己打开的软件全部可读。采样一遍约 8 毫秒。
public struct ProcessSampler: ProcessSampling {
    /// proc_pid_rusage 给的 CPU 时间是 mach 时间单位，要用 timebase 换算成纳秒（Apple 芯片上是 125/3）
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        if info.denom == 0 { info = mach_timebase_info_data_t(numer: 1, denom: 1) }
        return info
    }()

    public init() {}

    public func sampleAll() -> ProcessSnapshot {
        let timestamp = DispatchTime.now().uptimeNanoseconds
        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { return ProcessSnapshot(samples: [], timestampNanoseconds: timestamp) }
        var pids = [pid_t](repeating: 0, count: Int(estimated) + 64)      // 留点余量：列表期间可能有新进程
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard filled > 0 else { return ProcessSnapshot(samples: [], timestampNanoseconds: timestamp) }

        var samples: [ProcessSample] = []
        samples.reserveCapacity(Int(filled))
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            var usage = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
                }
            }
            guard status == 0 else { continue }                          // 无权读取或进程已退出
            let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            let path = length > 0 ? String(cString: pathBuffer) : ""
            let machTime = usage.ri_user_time + usage.ri_system_time
            let nanoseconds = machTime * UInt64(Self.timebase.numer) / UInt64(Self.timebase.denom)
            samples.append(ProcessSample(
                pid: pid,
                cpuNanoseconds: nanoseconds,
                footprintBytes: usage.ri_phys_footprint,
                path: path
            ))
        }
        return ProcessSnapshot(samples: samples, timestampNanoseconds: timestamp)
    }
}
```

- [ ] **Step 5: 运行全部测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 351 tests`，零警告。

- [ ] **Step 6: Commit**

```bash
git add Sources/SystemMonitorModule/HostStatsReader.swift Sources/SystemMonitorModule/ProcessSampler.swift Tests/SystemMonitorModuleTests/SystemReadersTests.swift
git commit -m "feat(monitor): kernel readers for host CPU ticks, memory statistics and per-process samples"
```

---

### Task 4: MonitorEngine —— 采样调度

**Files:**
- Create: `Sources/SystemMonitorModule/MonitorEngine.swift`
- Test: `Tests/SystemMonitorModuleTests/MonitorEngineTests.swift`

**Interfaces:**
- Consumes: `HostStatsReading`、`ProcessSampling`、`ProcessSnapshot`（Task 3）；`CPULoad.between`、`TopProcesses`、`MonitorSettings`（Task 2）
- Produces: `@MainActor public final class MonitorEngine`
  - `init(host:processes:settings:firstCPUListDelay: TimeInterval = 1.0, usesTimer: Bool = true)`
  - `struct Totals { cpu: CPULoad?; memory: MemoryUsage? }`、`struct TopLists { cpu: [TopEntry]?; memory: [TopEntry] }`（`cpu == nil` 表示"正在统计"）
  - `var onTotals: ((Totals) -> Void)?`、`var onTopLists: ((TopLists) -> Void)?`
  - `start()`、`stop()`、`applySettings()`、`refreshTotals()`、`setMenuOpen(_:)`、`menuDidOpen() async`、`tick() async`
  - 只读状态：`isMenuOpen`、`wantsTimer`、`lastTotals`

调度规则（设计文档 §4）：

| 状态 | 行为 |
|---|---|
| `showInMenuBar` 为 true，或菜单开着 | `wantsTimer == true`：按刷新间隔调 `tick()` |
| 两者都不是 | 没有定时器，`tick()` / `refreshTotals()` 什么都不做；旧的 CPU 快照作废 |
| 菜单开着 | `tick()` 读完总数后，在后台线程采样全部进程，回到主线程算排行 |
| `menuDidOpen()` | 立即 `tick()`（内存榜马上有，CPU 榜为 nil）→ 等 `firstCPUListDelay` → 再 `tick()`（CPU 榜出现） |
| 菜单关闭 | 丢弃进程样本；后台采样若此时才回来，结果被丢弃（用 `menuGeneration` 判断） |

`usesTimer: false` 和 `firstCPUListDelay: 0` 是给测试用的：不创建真的定时器、不睡眠，由测试直接 `await tick()`。

- [ ] **Step 1: 写失败的测试 `Tests/SystemMonitorModuleTests/MonitorEngineTests.swift`**

```swift
import Foundation
import Testing
@testable import SystemMonitorModule

private final class FakeHost: HostStatsReading {
    var ticksQueue: [CPUTicks?]
    var memory: MemoryUsage?
    private(set) var cpuReads = 0

    init(ticks: [CPUTicks?], memory: MemoryUsage?) {
        self.ticksQueue = ticks
        self.memory = memory
    }

    func cpuTicks() -> CPUTicks? {
        cpuReads += 1
        return ticksQueue.isEmpty ? nil : ticksQueue.removeFirst()
    }

    func memoryUsage() -> MemoryUsage? { memory }
}

/// 会在后台线程被调用，所以用锁保护。
private final class FakeSampler: ProcessSampling, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [ProcessSnapshot]
    private var calls = 0

    init(_ snapshots: [ProcessSnapshot]) {
        self.queue = snapshots
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return calls
    }

    func sampleAll() -> ProcessSnapshot {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        if queue.count > 1 { return queue.removeFirst() }
        return queue.first ?? ProcessSnapshot(samples: [], timestampNanoseconds: UInt64(calls))
    }
}

@MainActor
@Suite struct MonitorEngineTests {
    private let gigabyte: UInt64 = 1_073_741_824
    private let second: UInt64 = 1_000_000_000

    private func makeDefaults() -> UserDefaults {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func ticks(user: UInt32, idle: UInt32) -> CPUTicks {
        CPUTicks(cores: [CoreTicks(user: user, system: 0, idle: idle, nice: 0)])
    }

    private func snapshot(atSecond time: UInt64, chromeCPUMilliseconds: UInt64) -> ProcessSnapshot {
        ProcessSnapshot(
            samples: [
                ProcessSample(pid: 1, cpuNanoseconds: chromeCPUMilliseconds * 1_000_000, footprintBytes: 2 * gigabyte,
                              path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
                ProcessSample(pid: 2, cpuNanoseconds: 0, footprintBytes: gigabyte, path: "/usr/local/bin/node"),
            ],
            timestampNanoseconds: time * second)
    }

    private func makeEngine(host: FakeHost, sampler: FakeSampler, defaults: UserDefaults) -> MonitorEngine {
        MonitorEngine(host: host, processes: sampler, settings: MonitorSettings(defaults: defaults),
                      firstCPUListDelay: 0, usesTimer: false)
    }

    @Test func firstReadingHasMemoryButNoCPUAndSecondHasBoth() async {
        let memory = MemoryUsage(usedBytes: 8 * gigabyte, totalBytes: 16 * gigabyte)
        let host = FakeHost(ticks: [ticks(user: 0, idle: 0), ticks(user: 25, idle: 75)], memory: memory)
        let engine = makeEngine(host: host, sampler: FakeSampler([]), defaults: makeDefaults())
        var received: [MonitorEngine.Totals] = []
        engine.onTotals = { received.append($0) }

        engine.start()
        await engine.tick()

        #expect(received.count == 2)
        #expect(received[0] == MonitorEngine.Totals(cpu: nil, memory: memory))
        #expect(received[1].cpu?.total == 25)
        #expect(engine.lastTotals == received[1])
    }

    @Test func keepsLastCPUValueWhenTwoReadingsAreIdentical() async {
        let same = ticks(user: 25, idle: 75)
        let host = FakeHost(ticks: [ticks(user: 0, idle: 0), same, same], memory: nil)
        let engine = makeEngine(host: host, sampler: FakeSampler([]), defaults: makeDefaults())

        engine.start()
        await engine.tick()
        await engine.tick()

        #expect(engine.lastTotals.cpu?.total == 25)
    }

    @Test func kernelFailureShowsNoValue() async {
        let host = FakeHost(ticks: [ticks(user: 0, idle: 0), ticks(user: 50, idle: 50), nil], memory: nil)
        let engine = makeEngine(host: host, sampler: FakeSampler([]), defaults: makeDefaults())

        engine.start()
        await engine.tick()
        #expect(engine.lastTotals.cpu != nil)
        await engine.tick()

        #expect(engine.lastTotals == MonitorEngine.Totals(cpu: nil, memory: nil))
    }

    @Test func processesAreSampledOnlyWhileTheMenuIsOpen() async {
        let sampler = FakeSampler([snapshot(atSecond: 1, chromeCPUMilliseconds: 0)])
        let engine = makeEngine(host: FakeHost(ticks: [], memory: nil), sampler: sampler, defaults: makeDefaults())
        engine.start()

        await engine.tick()
        #expect(sampler.callCount == 0)

        engine.setMenuOpen(true)
        await engine.tick()
        #expect(sampler.callCount == 1)

        engine.setMenuOpen(false)
        await engine.tick()
        #expect(sampler.callCount == 1)
    }

    @Test func openingTheMenuGivesMemoryListAtOnceAndCPUListOnTheSecondSample() async {
        let sampler = FakeSampler([
            snapshot(atSecond: 10, chromeCPUMilliseconds: 1000),
            snapshot(atSecond: 11, chromeCPUMilliseconds: 1500),
        ])
        let engine = makeEngine(host: FakeHost(ticks: [], memory: nil), sampler: sampler, defaults: makeDefaults())
        var lists: [MonitorEngine.TopLists] = []
        engine.onTopLists = { lists.append($0) }
        engine.start()

        await engine.menuDidOpen()

        #expect(lists.count == 2)
        #expect(lists[0].cpu == nil)                                          // 正在统计…
        #expect(lists[0].memory.map(\.group.fallbackName) == ["Google Chrome", "node"])
        #expect(lists[1].cpu?.map(\.group.fallbackName) == ["Google Chrome"]) // node 是 0%，被过滤
        #expect(lists[1].cpu?.first?.value == 50)                             // 500 毫秒 / 1 秒
    }

    @Test func reopeningTheMenuStartsCountingFromScratch() async {
        let sampler = FakeSampler([
            snapshot(atSecond: 10, chromeCPUMilliseconds: 1000),
            snapshot(atSecond: 11, chromeCPUMilliseconds: 1500),
            snapshot(atSecond: 99, chromeCPUMilliseconds: 9000),
        ])
        let engine = makeEngine(host: FakeHost(ticks: [], memory: nil), sampler: sampler, defaults: makeDefaults())
        var lists: [MonitorEngine.TopLists] = []
        engine.onTopLists = { lists.append($0) }
        engine.start()
        await engine.menuDidOpen()
        engine.setMenuOpen(false)
        lists.removeAll()

        engine.setMenuOpen(true)
        await engine.tick()

        #expect(lists.count == 1)
        #expect(lists[0].cpu == nil)          // 不会拿关闭前的旧样本来算
    }

    @Test func nothingRunsWhenMenuBarDisplayIsOffAndMenuIsClosed() async {
        let defaults = makeDefaults()
        MonitorSettings(defaults: defaults).showInMenuBar = false
        let host = FakeHost(ticks: [ticks(user: 0, idle: 0)], memory: nil)
        let engine = makeEngine(host: host, sampler: FakeSampler([]), defaults: defaults)

        engine.start()
        await engine.tick()

        #expect(!engine.wantsTimer)
        #expect(host.cpuReads == 0)
    }

    @Test func openingTheMenuRunsTheTimerEvenWhenMenuBarDisplayIsOff() async {
        let defaults = makeDefaults()
        MonitorSettings(defaults: defaults).showInMenuBar = false
        let host = FakeHost(ticks: [ticks(user: 0, idle: 0), ticks(user: 10, idle: 90)], memory: nil)
        let engine = makeEngine(host: host, sampler: FakeSampler([]), defaults: defaults)
        engine.start()

        await engine.menuDidOpen()

        #expect(engine.wantsTimer)
        #expect(engine.lastTotals.cpu?.total == 10)      // 打开后的两次采样就能给出 CPU

        engine.setMenuOpen(false)
        #expect(!engine.wantsTimer)
    }

    @Test func applySettingsFollowsTheShowInMenuBarSwitch() {
        let defaults = makeDefaults()
        let engine = makeEngine(host: FakeHost(ticks: [], memory: nil), sampler: FakeSampler([]), defaults: defaults)
        engine.start()
        #expect(engine.wantsTimer)

        MonitorSettings(defaults: defaults).showInMenuBar = false
        engine.applySettings()
        #expect(!engine.wantsTimer)

        MonitorSettings(defaults: defaults).showInMenuBar = true
        engine.applySettings()
        #expect(engine.wantsTimer)
    }

    @Test func staleCPUBaselineIsDroppedWhileStopped() async {
        let defaults = makeDefaults()
        let host = FakeHost(ticks: [ticks(user: 0, idle: 0), ticks(user: 50, idle: 50), ticks(user: 950, idle: 1050)], memory: nil)
        let engine = makeEngine(host: host, sampler: FakeSampler([]), defaults: defaults)
        engine.start()
        await engine.tick()
        #expect(engine.lastTotals.cpu?.total == 50)

        MonitorSettings(defaults: defaults).showInMenuBar = false
        engine.applySettings()
        MonitorSettings(defaults: defaults).showInMenuBar = true
        engine.applySettings()
        await engine.tick()

        #expect(engine.lastTotals.cpu == nil)     // 停了一段时间：旧快照作废，要重新攒两份
    }

    @Test func refreshTotalsReadsImmediatelyButOnlyWhenSamplingIsWanted() {
        let defaults = makeDefaults()
        let host = FakeHost(ticks: [ticks(user: 0, idle: 0), ticks(user: 1, idle: 1)], memory: nil)
        let engine = makeEngine(host: host, sampler: FakeSampler([]), defaults: defaults)

        engine.refreshTotals()
        #expect(host.cpuReads == 0)          // 还没 start

        engine.start()
        engine.refreshTotals()
        #expect(host.cpuReads == 2)          // start 读一次 + 这一次

        MonitorSettings(defaults: defaults).showInMenuBar = false
        engine.applySettings()
        engine.refreshTotals()
        #expect(host.cpuReads == 2)          // 不显示、菜单也没开：不读
    }

    @Test func stopEndsEverything() async {
        let sampler = FakeSampler([snapshot(atSecond: 1, chromeCPUMilliseconds: 0)])
        let engine = makeEngine(host: FakeHost(ticks: [], memory: nil), sampler: sampler, defaults: makeDefaults())
        engine.start()
        engine.setMenuOpen(true)

        engine.stop()
        await engine.tick()

        #expect(!engine.wantsTimer)
        #expect(!engine.isMenuOpen)
        #expect(sampler.callCount == 0)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh --filter MonitorEngineTests`
Expected: 编译失败，`cannot find 'MonitorEngine' in scope`

- [ ] **Step 3: 写 `Sources/SystemMonitorModule/MonitorEngine.swift`**

```swift
import Foundation
import os

/// 采样调度。轻量的关键都在这里：
/// - 菜单栏显示开着：一个定时器，每次只读两个内核计数器（微秒级）；
/// - 菜单栏显示关着、菜单也没打开：什么都不运行；
/// - 菜单打开期间：额外在后台线程采样全部进程（约 8 毫秒），关闭后立刻停止并丢弃样本。
@MainActor
public final class MonitorEngine {
    public struct Totals: Equatable, Sendable {
        /// nil = 还没有两份快照，或读取失败
        public let cpu: CPULoad?
        public let memory: MemoryUsage?

        public init(cpu: CPULoad?, memory: MemoryUsage?) {
            self.cpu = cpu
            self.memory = memory
        }
    }

    public struct TopLists: Equatable, Sendable {
        /// nil = 正在统计（CPU 榜需要两次采样的差值）
        public let cpu: [TopEntry]?
        public let memory: [TopEntry]

        public init(cpu: [TopEntry]?, memory: [TopEntry]) {
            self.cpu = cpu
            self.memory = memory
        }
    }

    public var onTotals: ((Totals) -> Void)?
    public var onTopLists: ((TopLists) -> Void)?

    public private(set) var isMenuOpen = false
    /// 按当前状态是否应该有定时器在跑（菜单栏显示开着，或菜单正开着）
    public private(set) var wantsTimer = false
    public private(set) var lastTotals = Totals(cpu: nil, memory: nil)

    private let host: HostStatsReading
    private let processes: ProcessSampling
    private let settings: MonitorSettings
    private let firstCPUListDelay: TimeInterval
    private let usesTimer: Bool
    private let log = Logger(subsystem: "com.imiros.mykit", category: "monitor")

    private var timer: Timer?
    private var timerInterval = 0
    private var isStarted = false
    private var previousTicks: CPUTicks?
    private var lastLoad: CPULoad?
    private var previousSnapshot: ProcessSnapshot?
    /// 每次菜单开 / 关加一：后台采样回来时如果对不上，说明结果已经过时
    private var menuGeneration = 0
    private var isSamplingProcesses = false
    private var loggedFailures: Set<String> = []

    /// firstCPUListDelay：菜单打开后隔多久补第二次进程采样（CPU 榜要两次采样）。
    /// usesTimer = false 只在测试里用：不创建定时器，由测试直接调 tick()。
    public init(
        host: HostStatsReading = HostStatsReader(),
        processes: ProcessSampling = ProcessSampler(),
        settings: MonitorSettings = MonitorSettings(),
        firstCPUListDelay: TimeInterval = 1.0,
        usesTimer: Bool = true
    ) {
        self.host = host
        self.processes = processes
        self.settings = settings
        self.firstCPUListDelay = firstCPUListDelay
        self.usesTimer = usesTimer
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        applySettings()
        refreshTotals()           // 内存立刻就有；CPU 要等下一次才有差值
    }

    public func stop() {
        isStarted = false
        isMenuOpen = false
        menuGeneration += 1
        previousSnapshot = nil
        updateTimer()
    }

    /// 设置（是否显示、刷新间隔）变了之后调用，立即生效。
    public func applySettings() {
        updateTimer()
    }

    /// 菜单打开：立刻采样一次（内存榜马上有），约 1 秒后补第二次（CPU 榜出现），之后跟随定时器。
    public func menuDidOpen() async {
        setMenuOpen(true)
        let generation = menuGeneration
        await tick()
        if firstCPUListDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(firstCPUListDelay * 1_000_000_000))
        }
        guard isMenuOpen, generation == menuGeneration else { return }
        await tick()
    }

    public func setMenuOpen(_ open: Bool) {
        guard open != isMenuOpen else { return }
        isMenuOpen = open
        menuGeneration += 1
        previousSnapshot = nil        // 关闭即丢弃样本；重新打开从头统计
        updateTimer()
    }

    /// 立刻读一次总数（刚启动、刚改完设置时用，不用等一个间隔）。不该采样时什么都不做。
    public func refreshTotals() {
        guard isStarted, wantsTimer else { return }
        readTotals()
    }

    /// 一次刷新：读总数；菜单开着时再采样全部进程。定时器每次触发都调它，测试里直接调。
    public func tick() async {
        guard isStarted, wantsTimer else { return }
        readTotals()
        guard isMenuOpen else { return }
        await sampleProcesses()
    }

    // MARK: 总数

    private func readTotals() {
        let memory = host.memoryUsage()
        if memory == nil { logOnce("memory", "读取内存统计失败") }

        if let ticks = host.cpuTicks() {
            if let previous = previousTicks, let load = CPULoad.between(previous, ticks) {
                lastLoad = load       // 两次采样太近（Δ = 0）时沿用上一次的结果
            }
            previousTicks = ticks
        } else {
            logOnce("cpu", "读取 CPU 统计失败")
            previousTicks = nil
            lastLoad = nil
        }

        let totals = Totals(cpu: lastLoad, memory: memory)
        lastTotals = totals
        onTotals?(totals)
    }

    // MARK: 进程排行

    private func sampleProcesses() async {
        guard !isSamplingProcesses else { return }
        isSamplingProcesses = true
        defer { isSamplingProcesses = false }

        let generation = menuGeneration
        let sampler = processes
        let snapshot = await Task.detached(priority: .utility) { sampler.sampleAll() }.value
        guard isMenuOpen, generation == menuGeneration else { return }      // 期间菜单已经关了

        var cpu: [TopEntry]?
        if let previous = previousSnapshot, snapshot.timestampNanoseconds > previous.timestampNanoseconds {
            cpu = TopProcesses.byCPU(
                earlier: previous.samples,
                later: snapshot.samples,
                intervalNanoseconds: snapshot.timestampNanoseconds - previous.timestampNanoseconds
            )
        }
        previousSnapshot = snapshot
        onTopLists?(TopLists(cpu: cpu, memory: TopProcesses.byMemory(snapshot.samples)))
    }

    // MARK: 定时器

    private func updateTimer() {
        let wanted = isStarted && (settings.showInMenuBar || isMenuOpen)
        let interval = settings.interval
        if wanted == wantsTimer, !wanted || interval == timerInterval { return }

        wantsTimer = wanted
        timerInterval = interval
        timer?.invalidate()
        timer = nil

        guard wanted else {
            // 停止采样后，旧快照和现在隔得太久，下次不能拿来算差值
            previousTicks = nil
            lastLoad = nil
            return
        }
        guard usesTimer else { return }
        let timer = Timer(timeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.tick()
            }
        }
        timer.tolerance = TimeInterval(interval) * 0.2
        RunLoop.main.add(timer, forMode: .common)      // .common：菜单打开（事件跟踪模式）时也照常触发
        self.timer = timer
    }

    private func logOnce(_ key: String, _ message: String) {
        guard !loggedFailures.contains(key) else { return }
        loggedFailures.insert(key)
        log.error("\(message, privacy: .public)")
    }
}
```

- [ ] **Step 4: 运行全部测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 363 tests`，零警告。

- [ ] **Step 5: Commit**

```bash
git add Sources/SystemMonitorModule/MonitorEngine.swift Tests/SystemMonitorModuleTests/MonitorEngineTests.swift
git commit -m "feat(monitor): sampling engine - totals timer only while shown, process sampling only while the menu is open"
```

---

### Task 5: 界面、总装、使用说明、验收

**Files:**
- Create: `Sources/SystemMonitorModule/AppIconCache.swift`, `Sources/SystemMonitorModule/MonitorMenuViews.swift`, `Sources/SystemMonitorModule/MonitorSettingsView.swift`, `Sources/SystemMonitorModule/SystemMonitorModule.swift`
- Modify: `Package.swift`, `Sources/MyKit/AppDelegate.swift`, `README.md`
- Test: `Tests/SystemMonitorModuleTests/SystemMonitorModuleTests.swift`

**Interfaces:**
- Consumes: `MonitorEngine`（Task 4）；`MonitorFormat`、`MonitorSettings`、`TopProcesses.limit`、`AppGroup`、`TopEntry`（Task 2）；`AppModule` 的菜单开 / 关通知、`StatusBarController.setTitle`、`ModuleRegistry.menuItemsWithSeparators`（Task 1）；`Core.Toast`
- Produces: `@MainActor public final class SystemMonitorModule: NSObject, AppModule`
  - `init(defaults: UserDefaults = .standard, host: HostStatsReading = HostStatsReader(), processes: ProcessSampling = ProcessSampler(), firstCPUListDelay: TimeInterval = 1.0, usesTimer: Bool = true)`
  - `id == "monitor"`、`name == "系统监控"`
  - `var onMenuBarTitleChange: ((NSAttributedString?) -> Void)?`、`var currentMenuBarTitle: NSAttributedString?`（nil = 不显示文字）
  - `menuItems`：13 项 = CPU 标题行 + 5 个排行行 + 内存标题行 + 5 个排行行 +「打开活动监视器…」
  - `menuWillOpen()` / `menuDidClose()`、`settingsView`

界面要点：

- 标题行 / 排行行是 `NSMenuItem.view`（固定宽 300pt，手动布局）。菜单打开期间直接改标签文字即可实时更新；不足 5 个时把多余的菜单项 `isHidden = true`。
- CPU 榜为 nil → 第一行显示灰字"正在统计…"，其余行隐藏；榜为空 → "暂无明显占用"。每次 `menuWillOpen` 先把两个榜重置成"正在统计…"，不显示上一次打开时的旧数据。
- 菜单栏标题：`NSAttributedString`，12pt 等宽数字字体；最前面留一个空格与图标隔开；告警的数字段加 `systemRed`，其余段**不设颜色**（让系统按菜单栏深浅色自动处理）。
- 模块启动时状态栏还没创建，所以外壳在创建 `StatusBarController` 之后用 `currentMenuBarTitle` 补一次标题。
- 系统监控最先注册（菜单项排在最上面）；偏好设置里则排在最后。

- [ ] **Step 1: 写失败的测试 `Tests/SystemMonitorModuleTests/SystemMonitorModuleTests.swift`**

```swift
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
        #expect(titles == [" CPU --  内存 50%", " CPU --  内存 50%", " CPU 25%  内存 50%"])
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
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh --filter SystemMonitorModuleTests`
Expected: 编译失败，`cannot find 'SystemMonitorModule' in scope`

- [ ] **Step 3: 写 `Sources/SystemMonitorModule/AppIconCache.swift`**

```swift
import AppKit
import UniformTypeIdentifiers

/// 排行榜里每个软件的显示名和 16pt 图标。按分组键缓存，模块存活期间有效（也就几十个小图标）。
@MainActor
final class AppIconCache {
    struct Entry {
        let name: String
        let icon: NSImage
    }

    static let iconSize = NSSize(width: 16, height: 16)

    private var cache: [String: Entry] = [:]
    /// 不在 .app 里的进程（node、java 之类）用系统的"可执行文件"图标
    private lazy var genericIcon: NSImage = Self.sized(NSWorkspace.shared.icon(for: .unixExecutable))

    func entry(for group: AppGroup) -> Entry {
        if let cached = cache[group.key] { return cached }
        let entry: Entry
        if let bundlePath = group.bundlePath, FileManager.default.fileExists(atPath: bundlePath) {
            var name = FileManager.default.displayName(atPath: bundlePath)      // 本地化的名字，如"微信"
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            entry = Entry(
                name: name.isEmpty ? group.fallbackName : name,
                icon: Self.sized(NSWorkspace.shared.icon(forFile: bundlePath))
            )
        } else {
            entry = Entry(name: group.fallbackName, icon: genericIcon)
        }
        cache[group.key] = entry
        return entry
    }

    private static func sized(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = iconSize
        return copy
    }
}
```

- [ ] **Step 4: 写 `Sources/SystemMonitorModule/MonitorMenuViews.swift`**

```swift
import AppKit

/// 菜单里监控部分的宽度。自定义视图的菜单项需要自己定宽。
enum MonitorMenuMetrics {
    static let width: CGFloat = 300
    static let headerHeight: CGFloat = 24
    static let rowHeight: CGFloat = 20
    static let leftInset: CGFloat = 14
    static let rightInset: CGFloat = 14
}

/// 标题行：「CPU   42%      用户 35%   系统 7%」/「内存  63%      10.1 / 16 GB」
final class MonitorHeaderView: NSView {
    let titleLabel = NSTextField(labelWithString: "")
    let valueLabel = NSTextField(labelWithString: "--")
    let detailLabel = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: MonitorMenuMetrics.width, height: MonitorMenuMetrics.headerHeight))
        let height: CGFloat = 17
        let y = (MonitorMenuMetrics.headerHeight - height) / 2

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: MonitorMenuMetrics.leftInset, y: y, width: 40, height: height)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.frame = NSRect(x: titleLabel.frame.maxX + 4, y: y, width: 48, height: height)

        detailLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .right
        let detailX = valueLabel.frame.maxX + 4
        detailLabel.frame = NSRect(x: detailX, y: y, width: MonitorMenuMetrics.width - MonitorMenuMetrics.rightInset - detailX, height: height)

        for label in [titleLabel, valueLabel, detailLabel] {
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func update(value: String, detail: String, isWarning: Bool) {
        valueLabel.stringValue = value
        valueLabel.textColor = isWarning ? .systemRed : .labelColor
        detailLabel.stringValue = detail
    }
}

/// 排行行：图标 + 软件名 + 右对齐的数值。也用来显示"正在统计…"这类占位文字。
final class MonitorRowView: NSView {
    let iconView = NSImageView()
    let nameLabel = NSTextField(labelWithString: "")
    let valueLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: MonitorMenuMetrics.width, height: MonitorMenuMetrics.rowHeight))
        let height: CGFloat = 16
        let y = (MonitorMenuMetrics.rowHeight - height) / 2
        let iconX = MonitorMenuMetrics.leftInset + 10

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.frame = NSRect(x: iconX, y: y, width: 16, height: 16)

        let valueWidth: CGFloat = 72
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(
            x: MonitorMenuMetrics.width - MonitorMenuMetrics.rightInset - valueWidth, y: y, width: valueWidth, height: height)

        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        let nameX = iconView.frame.maxX + 6
        nameLabel.frame = NSRect(x: nameX, y: y, width: valueLabel.frame.minX - 6 - nameX, height: height)

        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(valueLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show(icon: NSImage, name: String, value: String) {
        iconView.image = icon
        nameLabel.stringValue = name
        nameLabel.textColor = .labelColor
        valueLabel.stringValue = value
    }

    /// 没有图标和数值的一行灰字，如"正在统计…"
    func showPlaceholder(_ text: String) {
        iconView.image = nil
        nameLabel.stringValue = text
        nameLabel.textColor = .secondaryLabelColor
        valueLabel.stringValue = ""
    }
}
```

- [ ] **Step 5: 写 `Sources/SystemMonitorModule/MonitorSettingsView.swift`**

```swift
import SwiftUI

struct MonitorSettingsView: View {
    @AppStorage private var showInMenuBar: Bool
    @AppStorage private var interval: Int
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        _showInMenuBar = AppStorage(wrappedValue: true, MonitorSettings.showInMenuBarKey, store: defaults)
        _interval = AppStorage(wrappedValue: MonitorSettings.defaultInterval, MonitorSettings.intervalKey, store: defaults)
    }

    var body: some View {
        Toggle("在菜单栏显示 CPU / 内存", isOn: $showInMenuBar)
            .onChange(of: showInMenuBar) { _, _ in notify() }
        Picker("刷新间隔", selection: $interval) {
            ForEach(MonitorSettings.allowedIntervals, id: \.self) { seconds in
                Text("\(seconds) 秒").tag(seconds)
            }
        }
        .onChange(of: interval) { _, _ in notify() }
        Text("点开右上角菜单可以看到最占 CPU / 内存的 5 个软件；排行只在菜单打开时统计，平时不占资源。")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func notify() {
        MonitorSettings(defaults: defaults).notifyChanged()      // 立即生效，无需重启
    }
}
```

- [ ] **Step 6: 写 `Sources/SystemMonitorModule/SystemMonitorModule.swift`**

```swift
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
```

- [ ] **Step 7: 更新 `Package.swift`（完整内容；MyKit 依赖 SystemMonitorModule）**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyKit",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Core"),
        .target(
            name: "ClipboardModule",
            dependencies: ["Core"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "ScreenshotModule", dependencies: ["Core"]),
        .target(name: "SystemMonitorModule", dependencies: ["Core"]),
        .executableTarget(
            name: "MyKit",
            dependencies: ["Core", "ClipboardModule", "ScreenshotModule", "SystemMonitorModule"]
        ),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "ClipboardModuleTests", dependencies: ["ClipboardModule"]),
        .testTarget(name: "ScreenshotModuleTests", dependencies: ["ScreenshotModule"]),
        .testTarget(name: "SystemMonitorModuleTests", dependencies: ["SystemMonitorModule"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 8: 替换 `Sources/MyKit/AppDelegate.swift`（最先注册监控模块、接标题、调整设置页顺序）**

```swift
import AppKit
import ClipboardModule
import Core
import ScreenshotModule
import SystemMonitorModule
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.imiros.mykit", category: "app")
    private let registry = ModuleRegistry()
    private let eventTap = GlobalKeyTap()
    private let hotkeys = HotkeySettings()
    private var hotkeyObservers: [NSObjectProtocol] = []
    private let accessibilityWatcher = AccessibilityWatcher()
    private let onboarding = OnboardingWindowController()
    private var clipboard: ClipboardModule?
    private var screenshot: ScreenshotModule?
    private var monitor: SystemMonitorModule?
    private var statusBar: StatusBarController?
    private var settingsWindow: SettingsWindowController?
    private var eventTapFailed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 系统监控最先注册：它的菜单项（CPU / 内存和排行榜）因此排在菜单最上面
        let monitor = SystemMonitorModule()
        monitor.onMenuBarTitleChange = { [weak self] title in
            self?.statusBar?.setTitle(title)
        }
        registry.register(monitor)
        self.monitor = monitor

        do {
            let clipboard = try ClipboardModule(databaseURL: ClipboardModule.defaultDatabaseURL)
            clipboard.onPausedChange = { [weak self] _ in self?.refreshIcon() }
            registry.register(clipboard)
            self.clipboard = clipboard
        } catch {
            log.error("剪切板模块初始化失败: \(String(describing: error), privacy: .public)")
        }

        let screenshot = ScreenshotModule()
        registry.register(screenshot)
        self.screenshot = screenshot

        registry.startAll()
        for failure in registry.failures {
            log.error("模块 \(failure.id, privacy: .public) 启动失败: \(String(describing: failure.error), privacy: .public)")
        }

        // 偏好设置里的顺序：剪切板、截图在前，系统监控放最后
        let settingsModules = registry.modules.filter { $0 !== monitor } + [monitor]
        let settingsWindow = SettingsWindowController(modules: settingsModules)
        self.settingsWindow = settingsWindow
        statusBar = StatusBarController(
            moduleMenuItems: registry.menuItemsWithSeparators,
            onOpenSettings: { settingsWindow.show() },
            onMenuWillOpen: { [weak self] in self?.registry.menuWillOpen() },
            onMenuDidClose: { [weak self] in self?.registry.menuDidClose() }
        )
        // 模块启动时状态栏还没创建，第一次的标题在这里补上
        statusBar?.setTitle(monitor.currentMenuBarTitle)

        eventTap.onDoubleTap = { [weak self] in
            self?.clipboard?.togglePanel()
        }
        applyHotkeys()
        observeHotkeySettings()
        accessibilityWatcher.onChange = { [weak self] trusted in
            self?.accessibilityChanged(trusted)
        }
        accessibilityWatcher.start()
        accessibilityChanged(accessibilityWatcher.isTrusted)

        log.info("MyKit 已启动，辅助功能授权=\(self.accessibilityWatcher.isTrusted), 剪切板需用户批准=\(Permissions.pasteboardNeedsUserApproval)")

        if clipboard?.recoveredFromCorruption == true {
            showDatabaseRecoveredAlert()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap.stop()
        accessibilityWatcher.stop()
        registry.stopAll()
    }

    /// 按当前设置（重新）注册快捷键。用户在偏好设置里改完立即调用，无需重启。
    private func applyHotkeys() {
        eventTap.unregisterAll()
        eventTap.doubleTapModifier = hotkeys.clipboardDoubleTap
        eventTap.register(hotkeys.screenshotCombo) { [weak self] in
            self?.screenshot?.startCapture()
        }
    }

    private func observeHotkeySettings() {
        let center = NotificationCenter.default
        hotkeyObservers = [
            center.addObserver(forName: HotkeySettings.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyHotkeys() }
            },
            // 设置页录制新快捷键期间暂停全局监听，否则现有快捷键会被吞掉、录不进去
            center.addObserver(forName: HotkeySettings.recordingDidBeginNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.eventTap.isSuspended = true }
            },
            center.addObserver(forName: HotkeySettings.recordingDidEndNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.eventTap.isSuspended = false }
            },
        ]
    }

    /// 授权状态变化（含启动时的首次检查）：有权限就开始监听双击 Option，没有就弹引导。
    private func accessibilityChanged(_ trusted: Bool) {
        if trusted {
            eventTapFailed = !eventTap.start()
            onboarding.close()
        } else {
            eventTap.stop()
            eventTapFailed = false
            onboarding.show()
        }
        refreshIcon()
    }

    private func refreshIcon() {
        if !accessibilityWatcher.isTrusted || eventTapFailed {
            statusBar?.setIcon(.warning)
        } else if clipboard?.isPaused == true {
            statusBar?.setIcon(.paused)
        } else {
            statusBar?.setIcon(.normal)
        }
    }

    private func showDatabaseRecoveredAlert() {
        let alert = NSAlert()
        alert.messageText = "剪切板历史已重建"
        alert.informativeText = "原来的历史数据库已损坏，MyKit 已将它备份并新建了一个空的历史。备份文件在 ~/Library/Application Support/MyKit/ 里。"
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
```

- [ ] **Step 9: 运行全部测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 379 tests`，零警告。

- [ ] **Step 10: 整体替换 README.md（增加系统监控一节）**

````markdown
# MyKit

Mac 菜单栏小工具箱。目前的功能：

- **剪切板历史** —— 双击 Option 呼出，保留最近 7 天复制过的文字，可搜索，回车直接粘贴；每条记录前面的图标表示它是从哪个 App 复制的。
- **截图** —— 按 `⇧⌘A`，框选或点选窗口，然后复制 / 保存 / 识别文字 / 贴在屏幕上。
- **系统监控** —— 右上角图标旁边一直显示 CPU 和内存占用；点开菜单能看到最占资源的 5 个软件。

## 安装

在"终端"里进入本目录，依次运行：

```bash
scripts/create-dev-cert.sh   # 只需要运行一次
scripts/build-app.sh
scripts/install.sh
```

完成后屏幕右上角会出现 MyKit 图标（三层叠起来的方块），旁边是 `CPU 12%  内存 63%` 这样的一行数字。

## 第一次使用：授权

MyKit 需要两项系统授权，都只需要做一次。

**辅助功能**（双击 Option、`⇧⌘A`、自动粘贴都靠它）—— 第一次启动会弹出引导窗口：

1. 点「打开系统设置」
2. 在「辅助功能」列表里找到 MyKit，打开右边的开关
3. 引导窗口会自动关闭，授权完成

**屏幕录制**（截图靠它）—— 第一次按 `⇧⌘A` 时会弹出引导窗口：

1. 点「打开系统设置」
2. 在「录屏与系统录音」列表里找到 MyKit，打开右边的开关
3. 回到引导窗口，点「重新启动 MyKit」（这项权限要重启后才生效）

如果右上角图标变成 ⚠️ 三角形，说明辅助功能授权丢失了，重新打开开关即可。
以后系统可能会定期询问"是否继续允许 MyKit 录制屏幕"，选「继续允许」。
第一次把截图保存到桌面时，系统会问"是否允许 MyKit 访问桌面文件夹"，选「允许」。

## 剪切板怎么用

| 操作 | 效果 |
|---|---|
| 快速按两下 Option | 打开 / 关闭剪切板面板 |
| 直接打字 | 搜索 |
| ↑ ↓ | 选择 |
| 回车 | 粘贴到刚才正在用的 App |
| ⌘1 – ⌘9 | 直接粘贴第 1–9 条 |
| ⌘⌫ | 删除选中的记录 |
| Esc 或点击面板外 | 关闭面板 |

## 截图怎么用

按 `⇧⌘A`（或点右上角图标 →「截图」），屏幕会定格并变暗：

- 把鼠标移到某个窗口上，它会变亮，**单击**就选中整个窗口；
- 或者**按住拖动**，框出任意一块区域；
- 选好后可以拖边上的小方块改大小、在选区里拖动改位置。

选区旁边会出现工具条：

| 按钮 | 键盘 | 效果 |
|---|---|---|
| 复制 | 回车 / `⌘C` / 双击选区 | 图片进剪切板，可以直接粘贴到微信、文档里 |
| 保存 | `⌘S` | 存成 PNG 文件（默认在桌面，可在偏好设置里改） |
| 识别文字 | `⌘R` | 打了马赛克的地方不会被识别，箭头、方框等其他标注不影响识别。**截图画面不关闭**，识别结果出现在选区旁边，方便对照原图；文字可以改、可以只选一部分，全文同时已自动复制。点「完成」或按 `Esc` 结束截图；点一下定格画面则收起结果、继续截图（可以调整选区再识别，或接着复制 / 保存 / 贴图） |
| 贴图 | `⌘T` | 截图原地浮在屏幕上，方便对照着看 |
| 取消 | Esc / 右键 | 逐级取消：正在打字 → 完成输入；选着标注工具 → 取消工具；有选区 → 清除选区（标注一起清掉）重新选；再按一次退出截图 |

### 标注

选好区域后，工具条左边有一排标注工具（鼠标停在按钮上会显示名字）。点一下选中，再点一次取消；选中后下面会多出一行，可以选 6 种颜色和 细 / 中 / 粗 三档，你的选择会被记住。

| 工具 | 怎么用 |
|---|---|
| 方框 / 椭圆 | 按住拖动。按住 `Shift` 画正方形 / 正圆 |
| 箭头 / 直线 | 从起点拖到终点。按住 `Shift` 吸附到水平、垂直或 45° |
| 画笔 | 随手涂画 |
| 荧光笔 | 半透明的粗线，给文字做高亮。按住 `Shift` 画直线 |
| 文字 | 点一下出现输入框，直接打字（支持中文输入法，回车换行），点别处或按 `Esc` 完成 |
| 马赛克 | 拖出一个矩形，里面变成方块，用来遮手机号、密码等 |
| 序号 | 每点一下放一个 ①②③…，自动递增 |

- 画错了按 `⌘Z` 撤销，`⇧⌘Z` 重做（工具条上也有按钮）。画好的标注不能再选中移动，撤销重画即可。
- 标注只能画在选区里面。
- 选了工具或已经有标注时，选区不能再移动 / 改大小；想调整选区，先把标注全部撤销并取消选中工具。
- 复制 / 保存 / 贴图得到的图片都带标注。

**翻译成中文**：识别结果面板上有一个「翻译成中文」勾选框。勾上后，面板下半部分显示中文译文（旁边有「复制译文」），并且**以后每次识别完都会自动翻译**，直到你取消勾选。只翻译英文；识别内容里没有英文时会提示"没有可翻译的英文"。翻译用的是 macOS 自带的翻译功能：离线、免费、不用注册。翻译时截图画面**不会关闭**。**第一次使用**时系统会提示下载英译中语言包（只需一次）：这时截图画面会临时让出窗口层级（画面还在，菜单栏会露出来），好让系统的下载提示显示在上面；点「下载」，完成后重新勾选一次「翻译成中文」即可。如果没有看到下载提示，可以手动下载：系统设置 → 通用 → 语言与地区 → 翻译语言，下载「英语」和「简体中文」。需要 macOS 15 或更新的系统。

**贴图**：拖动可以移动，滚轮缩放，双击关闭；右键有 复制 / 保存 / 识别文字 / 关闭 / 关闭全部贴图。右上角菜单里也有「关闭所有贴图」。

## 系统监控怎么用

- **菜单栏**：MyKit 图标右边一直显示 `CPU 12%  内存 63%`，默认每 2 秒刷新一次。哪一项到了 85% 或更高，那个数字会变成红色。刚启动的头两秒 CPU 显示 `--`（需要两次读数才能算出占用），属正常。
- **点开菜单**：最上面是 CPU 和内存的总数（CPU 还分"用户 / 系统"，内存显示"已用 / 总量"），下面各列出最占资源的 5 个软件，带图标。内存榜一打开就有；CPU 榜要统计约 1 秒，之前显示"正在统计…"。菜单开着的时候排行会持续刷新，关上就停止统计。
- 同一个软件的所有辅助进程会合并成一项（比如 Chrome 的几十个 Helper 都算在"Google Chrome"头上）。
- 单个软件的 CPU 百分比和系统的"活动监视器"算法一致：占满一个核心是 100%，同时用多个核心可以超过 100%。所以它可能比菜单栏上的总 CPU 数字大，这是正常的（总数是占全部核心的比例）。
- 系统自己的后台进程（WindowServer、kernel_task 等）普通软件读不到，不会出现在排行里；你自己打开的软件都在。
- 「打开活动监视器…」会启动系统自带的那个工具。MyKit 不提供"结束进程"这类有风险的操作。
- **设置**：「偏好设置…」→「系统监控」里可以关掉菜单栏上的数字（关掉后点开菜单仍然能看），也可以把刷新间隔改成 1 秒 / 2 秒 / 5 秒，改完立即生效。

系统监控不需要任何授权，不联网，不调用外部命令，数据直接从 macOS 内核读取。平时每次刷新只读两个计数器；排行榜只在菜单打开时才统计。

## 修改快捷键

点右上角图标 →「偏好设置…」，改完**立即生效**，不用重启：

- **截图快捷键**：在「截图」一栏点一下显示着 `⇧⌘A` 的按钮 → 它会变成"请按下新的快捷键…" → 按下你想要的组合键即可（按 `Esc` 取消；15 秒不按自动取消）。普通按键必须带 `⌘`、`⌃` 或 `⌥` 之一；`F1`–`F12` 可以单独用。复制 / 粘贴 / 退出这类系统常用键不允许设置。旁边的「恢复默认」会改回 `⇧⌘A`。
- **剪切板呼出方式**：在「剪切板历史」一栏的「呼出方式」里选 双击 Option / 双击 Control / 双击 Command。

**快捷键说明：** `⇧⌘A` 在个别 App 里原本有别的用途（访达里是打开「应用程序」文件夹，Chrome 里是搜索标签页）；MyKit 运行时这个键优先用于截图。钉钉的截图默认也是 `⇧⌘A`，如果按下后出来的是钉钉的截图，到钉钉「设置 → 快捷键」里把截图快捷键关掉或改成别的键。

## 退出

**左键或右键**点击右上角的 MyKit 图标 →「退出 MyKit」。

同一个菜单里还有：CPU / 内存和排行榜、打开活动监视器、打开剪切板、暂停记录、截图、关闭所有贴图、偏好设置（保留天数、开机自启、清空历史、截图保存位置、系统监控的显示与刷新间隔）。

## 数据在哪里

剪切板历史：`~/Library/Application Support/MyKit/clipboard.sqlite`，只保存在本机，不联网。从密码管理器复制的密码不会被记录。
截图：只有你点「保存」时才会写文件；文字识别在本机完成，不联网。
系统监控：只在内存里保留最近一次的读数，不写任何文件。

## 更新

改了代码之后重新运行 `scripts/build-app.sh && scripts/install.sh`，不需要重新授权。

## 开发

```bash
scripts/test.sh                                   # 跑全部单元测试
scripts/test.sh --filter SelectionModelTests      # 只跑一组
```

设计文档：`docs/superpowers/specs/`；实现计划：`docs/superpowers/plans/`
````

- [ ] **Step 11: 构建、安装、确认启动**

Run:

```bash
scripts/build-app.sh
scripts/install.sh
sleep 4
/usr/bin/log show --last 1m --predicate 'subsystem == "com.imiros.mykit"' --info | grep -E "MyKit 已启动|失败"
ps -o %cpu=,rss= -p "$(pgrep -x MyKit)"
```

Expected: 构建输出 `designated => identifier "com.imiros.mykit" …` 和 `完成：build/MyKit.app`；日志里有 `MyKit 已启动`，没有"失败"；`ps` 显示 MyKit 自己的 CPU 占用接近 0（0.0–1.0）。

- [ ] **Step 12: 手动验收（需要人来操作；逐条确认，任何一条不符合就修复后重测）**

1. 看屏幕右上角。→ MyKit 图标右边出现 `CPU 12%  内存 63%` 这样的文字（刚启动的头两秒 CPU 是 `--`）。
2. 盯着看十秒。→ 数字大约每 2 秒变一次；数字变化时，右边其他菜单栏图标**不会左右抖动**。
3. 打开一个吃 CPU 的东西（比如用 Chrome 播放一个高清视频，或同时打开很多网页）。→ CPU 数字明显上升。
4. 点一下 MyKit 图标。→ 菜单最上面是「CPU  xx%   用户 xx%  系统 xx%」，下面最多 5 行软件；再下面是「内存 xx%   已用 / 总量 GB」和最多 5 行软件；然后是「打开活动监视器…」、一条分隔线，再往下才是「打开剪切板」等原有菜单项。
5. 注意刚点开的那一瞬间。→ 内存榜立刻就有；CPU 榜先显示灰色的"正在统计…"，约 1 秒后变成软件列表。
6. 菜单开着别关，看几秒。→ 排行和数字会持续刷新，菜单不卡、鼠标移动高亮正常。
7. 看排行里的名字和图标。→ 是软件本来的图标和中文名（如"微信"）；Chrome 只出现一行"Google Chrome"，而不是一堆"Google Chrome Helper"。
8. 点「打开活动监视器…」，和它对照。→ 排在前面的软件大体一致；单个软件的 CPU% 数量级一致（活动监视器里是分进程列的，MyKit 是合并后的，所以 MyKit 的数字会更大一些）；内存总量一致。
9. 关掉菜单，再右键点图标。→ 弹出的是同一个菜单，监控数据同样显示。
10. 如果某一项到了 85% 以上（内存比较容易：多开几个大软件）。→ 菜单栏上那个数字变红，菜单里标题行的百分比也变红；降下来后恢复。
11. 「偏好设置…」→ 最下面有「系统监控」一栏。关掉「在菜单栏显示 CPU / 内存」。→ 菜单栏立刻只剩图标；点开菜单，监控数据仍然有（CPU 总数和 CPU 榜都在约 1 秒后出现）。
12. 重新打开这个开关。→ 文字马上回来（CPU 先是 `--`，一个刷新间隔后有数字）。
13. 把刷新间隔改成 1 秒、再改成 5 秒。→ 菜单栏数字的变化节奏立刻跟着变，不用重启。
14. 退出 MyKit 再打开。→ 上面两项设置都还记得。
15. 回归检查：双击 Option 的剪切板、`⇧⌘A` 截图（含标注、识别文字）、菜单里的「暂停记录」（图标变灰，文字还在）都和以前一样。
16. 在「活动监视器」里找到 MyKit。→ 菜单关着时 CPU 占用接近 0%（0.0–0.5%）；菜单打开时略有上升，关上后回落。内存没有持续增长。

- [ ] **Step 13: Commit**

```bash
git add Package.swift Sources Tests README.md
git commit -m "feat: system monitor module - CPU and memory in the menu bar, top 5 apps in the menu, settings and README"
```
