import Foundation
import Testing
@testable import UninstallerModule

/// 记录假执行器收到的调用，并让测试控制每个假操作的返回值。
private final class FakeSystem: @unchecked Sendable {
    private let lock = NSLock()
    private var _trashCalls: [[String]] = []
    private var _quitCalls = 0

    var list = InstalledAppList()
    var leftovers: [String: LeftoverScanResult] = [:]          // 键：软件路径
    var scanDelays: [String: TimeInterval] = [:]
    var sizes: [String: UInt64] = [:]                          // 键：文件名
    var running = false
    var quitSucceeds = true
    var report = TrashReport()
    var protectedBundleIDs: Set<String> = ["com.apple.Safari"]

    var trashCalls: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return _trashCalls
    }

    var quitCalls: Int {
        lock.lock(); defer { lock.unlock() }
        return _quitCalls
    }

    func recordTrash(_ items: [LeftoverItem]) {
        lock.lock(); defer { lock.unlock() }
        _trashCalls.append(items.map(\.url.lastPathComponent))
    }

    func recordQuit() {
        lock.lock(); defer { lock.unlock() }
        _quitCalls += 1
    }

    func dependencies() -> UninstallerDependencies {
        UninstallerDependencies(
            listApps: { self.list },
            scanLeftovers: { identity, _, _ in
                if let delay = self.scanDelays[identity.url.path] { Thread.sleep(forTimeInterval: delay) }
                return self.leftovers[identity.url.path] ?? LeftoverScanResult()
            },
            sizeOf: { url, _ in self.sizes[url.lastPathComponent] },
            makeApp: { url in
                InstalledApp(
                    identity: AppIdentity(url: url, bundleID: url.lastPathComponent.hasPrefix("Safari") ? "com.apple.Safari" : "org.example.dropped",
                                          names: [url.deletingPathExtension().lastPathComponent]),
                    title: url.deletingPathExtension().lastPathComponent)
            },
            isProtected: { _, bundleID in bundleID.map { self.protectedBundleIDs.contains($0) } ?? false },
            isRunning: { _ in self.running },
            quit: { _ in
                self.recordQuit()
                return self.quitSucceeds
            },
            trash: { items, _ in
                self.recordTrash(items)
                return self.report
            }
        )
    }
}

@MainActor
@Suite struct UninstallerViewModelTests {
    private func app(_ name: String, id: String, size: UInt64? = nil) -> InstalledApp {
        InstalledApp(
            identity: AppIdentity(url: URL(fileURLWithPath: "/Applications/\(name).app"), bundleID: id, names: [name]),
            title: name, sizeBytes: size)
    }

    private func item(_ path: String, _ confidence: Confidence = .certain, admin: Bool = false, isApp: Bool = false) -> LeftoverItem {
        LeftoverItem(url: URL(fileURLWithPath: path), category: "测试", confidence: confidence, needsAdmin: admin, isAppBundle: isApp)
    }

    /// 一个装了 Tool 和 Other 两个软件的世界；Tool 有 4 条相关项。
    private func makeWorld() -> (FakeSystem, UninstallerViewModel, InstalledApp, InstalledApp) {
        let system = FakeSystem()
        let tool = app("Tool", id: "org.example.tool")
        let other = app("Other", id: "org.example.other")
        system.list = InstalledAppList(apps: [tool, other], allBundleIDs: ["org.example.tool", "org.example.other", "com.apple.Safari"])
        system.leftovers[tool.id] = LeftoverScanResult(items: [
            item("/Applications/Tool.app", isApp: true),
            item("/Users/t/Library/Preferences/org.example.tool.plist"),
            item("/Users/t/.tool", .possible),
            item("/Library/LaunchDaemons/org.example.tool.plist", admin: true),
        ], unreadableLocations: [URL(fileURLWithPath: "/Users/t/Library/Containers")])
        system.leftovers[other.id] = LeftoverScanResult(items: [item("/Applications/Other.app", isApp: true)])
        system.sizes = ["Tool.app": 1_048_576 * 300, "org.example.tool.plist": 4096, ".tool": 1_048_576 * 35, "Other.app": 1_048_576 * 10]
        return (system, UninstallerViewModel(dependencies: system.dependencies()), tool, other)
    }

    @Test func loadListsAppsThenSizesArriveOneByOne() async {
        let (_, vm, _, _) = makeWorld()

        await vm.load()
        #expect(vm.visibleApps.map(\.title) == ["Other", "Tool"])
        #expect(vm.visibleApps.allSatisfy { $0.sizeBytes == nil })
        #expect(!vm.isLoadingApps)

        await vm.computeAppSizes()
        vm.sortOrder = .size
        #expect(vm.visibleApps.map(\.title) == ["Tool", "Other"])
    }

    @Test func searchFiltersTheVisibleList() async {
        let (_, vm, _, _) = makeWorld()
        await vm.load()
        vm.query = "oth"
        #expect(vm.visibleApps.map(\.title) == ["Other"])
    }

    @Test func selectingAnAppScansGroupsAndChecksOnlyCertainItems() async {
        let (_, vm, tool, _) = makeWorld()
        await vm.load()

        await vm.select(tool)

        #expect(vm.phase == .ready)
        #expect(vm.groups.map(\.id) == ["certain", "possible", "admin"])
        #expect(vm.groups[0].items.map(\.url.lastPathComponent) == ["Tool.app", "org.example.tool.plist"])
        #expect(vm.groups[1].title == "可能相关（默认不勾选，请自己判断）")
        #expect(vm.checkedItems.map(\.url.lastPathComponent) == ["Tool.app", "org.example.tool.plist", "org.example.tool.plist"])
        #expect(!vm.isChecked(vm.groups[1].items[0]))
        #expect(vm.unreadableLocations.map(\.lastPathComponent) == ["Containers"])
        #expect(vm.summaryText == "已选 3 项，300 MB")
    }

    @Test func checkboxesSelectAllAndOnlyCertain() async throws {
        let (_, vm, tool, _) = makeWorld()
        await vm.load()
        await vm.select(tool)
        let hidden = try #require(vm.items.first { $0.url.lastPathComponent == ".tool" })

        vm.setChecked(hidden, true)
        #expect(vm.summaryText == "已选 4 项，335 MB")

        vm.selectOnlyCertain()
        #expect(vm.checkedItems.count == 3)

        vm.selectAll()
        #expect(vm.checkedItems.count == 4)

        for entry in vm.items { vm.setChecked(entry, false) }
        #expect(!vm.canUninstall)
        #expect(vm.summaryText == "已选 0 项，0 KB")
    }

    @Test func selectingAnotherAppDropsTheSlowerPreviousScan() async throws {
        let (system, vm, tool, other) = makeWorld()
        await vm.load()
        system.scanDelays[tool.id] = 0.3

        let slow = Task { await vm.select(tool) }
        try await Task.sleep(nanoseconds: 50_000_000)
        await vm.select(other)
        await slow.value

        #expect(vm.selectedApp?.title == "Other")
        #expect(vm.items.map(\.url.lastPathComponent) == ["Other.app"])
        #expect(vm.phase == .ready)
    }

    @Test func knownAppSizeIsReusedForTheBundleRow() async {
        let (system, vm, _, _) = makeWorld()
        let sized = app("Tool", id: "org.example.tool", size: 777)
        system.list.apps = [sized]
        system.sizes["Tool.app"] = 999_999
        await vm.load()

        await vm.select(sized)

        #expect(vm.items.first { $0.isAppBundle }?.sizeBytes == 777)
    }

    @Test func uninstallAsksForConfirmationThenTrashesCheckedItemsOnly() async {
        let (system, vm, tool, _) = makeWorld()
        await vm.load()
        await vm.select(tool)
        var report = TrashReport()
        report.succeeded = vm.checkedItems
        system.report = report

        vm.requestUninstall()
        #expect(vm.phase == .confirming)
        #expect(vm.confirmationText == "将把 3 项（300 MB）移到废纸篓。可以从废纸篓恢复。")
        #expect(system.trashCalls.isEmpty)                         // 确认之前什么都不动

        await vm.confirm()

        #expect(system.trashCalls == [["Tool.app", "org.example.tool.plist", "org.example.tool.plist"]])
        #expect(vm.phase == .finished(report))
    }

    @Test func cancellingTheConfirmationChangesNothing() async {
        let (system, vm, tool, _) = makeWorld()
        await vm.load()
        await vm.select(tool)

        vm.requestUninstall()
        vm.cancelPending()
        await vm.confirm()                                         // 不在确认状态：无效

        #expect(vm.phase == .ready)
        #expect(system.trashCalls.isEmpty)
    }

    @Test func runningAppMustQuitFirst() async {
        let (system, vm, tool, _) = makeWorld()
        system.running = true
        await vm.load()
        await vm.select(tool)

        vm.requestUninstall()
        #expect(vm.phase == .needsQuit)

        await vm.quitAndContinue()
        #expect(system.quitCalls == 1)
        #expect(vm.phase == .confirming)
    }

    @Test func appThatRefusesToQuitStopsTheFlowWithANotice() async {
        let (system, vm, tool, _) = makeWorld()
        system.running = true
        system.quitSucceeds = false
        await vm.load()
        await vm.select(tool)

        vm.requestUninstall()
        await vm.quitAndContinue()

        #expect(vm.phase == .ready)
        #expect(vm.notice == "「Tool」没有退出，请手动退出它之后再试")
        #expect(system.trashCalls.isEmpty)
    }

    @Test func runningCheckIsSkippedWhenTheAppItselfIsNotBeingRemoved() async throws {
        let (system, vm, tool, _) = makeWorld()
        system.running = true
        await vm.load()
        await vm.select(tool)
        let bundle = try #require(vm.items.first { $0.isAppBundle })

        vm.setChecked(bundle, false)                               // 只清残留，不删本体
        vm.requestUninstall()

        #expect(vm.phase == .confirming)
    }

    @Test func afterRemovingTheAppItLeavesTheList() async {
        let (system, vm, tool, _) = makeWorld()
        await vm.load()
        await vm.select(tool)
        var report = TrashReport()
        report.succeeded = vm.checkedItems
        system.report = report
        vm.requestUninstall()
        await vm.confirm()

        await vm.dismissResult()

        #expect(vm.apps.map(\.title) == ["Other"])
        #expect(vm.selectedApp == nil)
        #expect(vm.items.isEmpty)
        #expect(vm.phase == .idle)
    }

    @Test func whenTheAppSurvivesTheListIsRescanned() async {
        let (system, vm, tool, _) = makeWorld()
        await vm.load()
        await vm.select(tool)
        var report = TrashReport()
        report.failed = [TrashFailure(item: vm.items[0], reason: "需要管理员密码，你取消了输入")]
        system.report = report
        vm.requestUninstall()
        await vm.confirm()

        await vm.dismissResult()

        #expect(vm.apps.count == 2)
        #expect(vm.selectedApp?.title == "Tool")
        #expect(vm.phase == .ready)
    }

    @Test func droppingAnAppSelectsItAndAddsItToTheList() async {
        let (system, vm, _, _) = makeWorld()
        await vm.load()
        let dropped = URL(fileURLWithPath: "/Users/t/Downloads/Dropped.app")
        system.leftovers[dropped.path] = LeftoverScanResult(items: [item(dropped.path, isApp: true)])

        let accepted = await vm.handleDrop(dropped)

        #expect(accepted)
        #expect(vm.selectedApp?.title == "Dropped")
        #expect(vm.apps.count == 3)
        #expect(vm.phase == .ready)
    }

    @Test func droppingASystemAppOrANonAppIsRefused() async {
        let (_, vm, _, _) = makeWorld()
        await vm.load()

        let safari = await vm.handleDrop(URL(fileURLWithPath: "/Applications/Safari.app"))
        #expect(safari)
        #expect(vm.notice == "这是系统软件，不能卸载")
        #expect(vm.selectedApp == nil)

        let document = await vm.handleDrop(URL(fileURLWithPath: "/Users/t/Documents/report.pdf"))
        #expect(!document)
    }

    @Test func teardownReleasesEverything() async {
        let (_, vm, tool, _) = makeWorld()
        await vm.load()
        await vm.select(tool)

        vm.teardown()

        #expect(vm.apps.isEmpty)
        #expect(vm.items.isEmpty)
        #expect(vm.selectedApp == nil)
        #expect(vm.phase == .idle)
    }
}

@Suite struct PathDisplayTests {
    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    @Test func homeIsAbbreviatedWithATilde() {
        #expect(PathDisplay.abbreviated(URL(fileURLWithPath: "/Users/tester/Library/Caches/x"), home: home) == "~/Library/Caches/x")
        #expect(PathDisplay.abbreviated(home, home: home) == "~")
        #expect(PathDisplay.abbreviated(URL(fileURLWithPath: "/Library/LaunchDaemons/x.plist"), home: home) == "/Library/LaunchDaemons/x.plist")
        #expect(PathDisplay.abbreviated(URL(fileURLWithPath: "/Users/tester2/file"), home: home) == "/Users/tester2/file")
    }

    @Test func locationIsTheParentFolder() {
        #expect(PathDisplay.location(of: URL(fileURLWithPath: "/Users/tester/.docker"), home: home) == "~")
        #expect(PathDisplay.location(of: URL(fileURLWithPath: "/Applications/Tool.app"), home: home) == "/Applications")
    }
}
