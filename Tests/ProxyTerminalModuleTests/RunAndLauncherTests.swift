import Foundation
import Testing
@testable import ProxyTerminalModule

@MainActor
final class FakeDriver: TerminalDriving {
    var opened: [PaneSpec] = []
    var screens: [String: String] = [:]
    var applied: [[PaneUpdate]] = []
    var openError: TerminalError?
    var windowGone = false

    func open(panes: [PaneSpec]) throws -> OpenedWindow {
        if let openError { throw openError }
        opened = panes
        return OpenedWindow(windowID: 9, sessionIDs: panes.indices.map { "S\($0)" })
    }

    func contents(windowID: Int) throws -> [String: String] {
        if windowGone { throw TerminalError.windowClosed }
        return screens
    }

    func apply(_ updates: [PaneUpdate], windowID: Int) throws {
        applied.append(updates)
    }
}

final class RecordingPassAction: ProxyPassAction {
    var asked: [String] = []
    func command(verifiedAddress: String) -> String? {
        asked.append(verifiedAddress)
        return "next \(verifiedAddress)"
    }
}

@MainActor
@Suite struct ProxyTerminalRunTests {
    let commands = PaneCommands(token: 500_000)
    let start = Date(timeIntervalSince1970: 1000)

    func finished(_ result: String) -> String {
        "\(commands.checkIP)\n\(result)\n\n\(commands.marker)\n"
    }

    func makeRun(folders: [String], driver: FakeDriver, action: RecordingPassAction? = nil,
                 expectedIP: String = "1.2.3.4") throws -> ProxyTerminalRun {
        let action = action ?? RecordingPassAction()
        let preset = TerminalPreset(name: "工作", expectedIP: expectedIP, folders: folders)
        let run = ProxyTerminalRun(preset: preset, driver: driver, passAction: action, commands: commands)
        try run.start(at: start)
        return run
    }

    @Test func opensOnePanePerFolderWithCommands() throws {
        let driver = FakeDriver()
        _ = try makeRun(folders: ["/w/api", "/w/web", "/x/api"], driver: driver)
        #expect(driver.opened.map(\.title) == ["api", "web", "api (2)"])
        #expect(driver.opened[0].lines == [commands.enterFolder("/w/api", title: "api"), commands.checkIP])
        #expect(driver.opened[2].lines[0] == commands.enterFolder("/x/api", title: "api (2)"))
    }

    @Test func passesMatchingPanesAndMarksOthers() throws {
        let driver = FakeDriver()
        let action = RecordingPassAction()
        let run = try makeRun(folders: ["/w/api", "/w/web", "/w/db"], driver: driver, action: action)

        driver.screens = ["S0": finished("1.2.3.4"), "S1": finished("5.6.7.8"), "S2": commands.checkIP]
        #expect(run.poll(at: start.addingTimeInterval(2)) == false)
        #expect(run.panes.map(\.state) == [.passed("1.2.3.4"), .wrongAddress("5.6.7.8"), .waiting])
        #expect(action.asked == ["1.2.3.4"])
        #expect(driver.applied.last == [
            PaneUpdate(sessionID: "S0", title: "api ✅ 1.2.3.4", markFailed: false, typeText: "next 1.2.3.4"),
            PaneUpdate(sessionID: "S1", title: "web ❌ 5.6.7.8", markFailed: true),
            PaneUpdate(sessionID: "S2", title: "db", markFailed: false),
        ])

        // 已出结果的块不再更新，也不会重复执行下一步
        #expect(run.poll(at: start.addingTimeInterval(16)) == true)
        #expect(run.panes[2].state == .timedOut)
        #expect(driver.applied.last == [PaneUpdate(sessionID: "S2", title: "db ❌ 超时", markFailed: true)])
        #expect(action.asked == ["1.2.3.4"])
        #expect(run.summary == "3 个终端：1 个 IP 正确，web 不对（实际 5.6.7.8）、db 超时")
    }

    /// 核对失败的任何情况都绝不能输入下一步的命令
    @Test func failedPanesNeverGetTheNextCommand() throws {
        let driver = FakeDriver()
        let action = RecordingPassAction()
        let run = try makeRun(folders: ["/a", "/b", "/c", "/d", "/e"], driver: driver, action: action)
        driver.screens = [
            "S0": finished("1.2.3.40"),                         // 只差一位
            "S1": finished("2001:db8::1"),
            "S2": finished(""),                                  // curl 什么都没拿到
            "S3": commands.checkIP,                              // 一直没执行完
            // S4 那块被关掉了
        ]
        #expect(run.poll(at: start.addingTimeInterval(20)) == true)
        #expect(run.panes.map(\.state) == [.wrongAddress("1.2.3.40"), .wrongAddress("2001:db8::1"), .noAddress, .timedOut, .closed])
        #expect(action.asked.isEmpty)
        #expect(driver.applied.flatMap { $0 }.allSatisfy { $0.typeText == nil })

        // 预期 IP 没填（不该出现，小窗口会拦住）时也不能算通过
        let driver2 = FakeDriver()
        let run2 = try makeRun(folders: ["/a"], driver: driver2, action: action, expectedIP: "")
        driver2.screens = ["S0": finished("1.2.3.4")]
        #expect(run2.poll(at: start) == true)
        #expect(run2.panes[0].state == .wrongAddress("1.2.3.4"))
        #expect(action.asked.isEmpty)
    }

    @Test func launchClaudeCountsDownThenRechecksAddressInShell() {
        let command = LaunchClaude().command(verifiedAddress: "1.2.3.4")
        #expect(command == #"for i in 5 4 3 2 1; do printf '\r✅ IP 核对通过，%s 秒后启动 claude（按 Ctrl+C 取消）' $i; sleep 1; done; echo; "#
            + #"if [ "$(curl -s --max-time 10 ip.sb)" = '1.2.3.4' ]; then CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1 claude; "#
            + "else echo '❌ 出口 IP 和核对时不一致，已阻止启动 claude'; fi")
        #expect(NoPassAction().command(verifiedAddress: "1.2.3.4") == nil)
    }

    @Test func allCorrectSummary() throws {
        let driver = FakeDriver()
        let run = try makeRun(folders: ["/a", "/b"], driver: driver)
        driver.screens = ["S0": finished("1.2.3.4"), "S1": finished("1.2.3.4")]
        #expect(run.poll(at: start) == true)
        #expect(run.summary == "2 个终端 IP 全部正确")
    }

    @Test func curlWithoutOutputCountsAsNoAddress() throws {
        let driver = FakeDriver()
        let run = try makeRun(folders: ["/a"], driver: driver)
        driver.screens = ["S0": finished("")]
        #expect(run.poll(at: start) == true)
        #expect(run.panes[0].state == .noAddress)
        #expect(run.summary == "1 个终端：0 个 IP 正确，a 没拿到 IP")
    }

    @Test func closedWindowFinishesRun() throws {
        let driver = FakeDriver()
        let run = try makeRun(folders: ["/a", "/b"], driver: driver)
        driver.screens = ["S0": finished("1.2.3.4")]   // S1 那块被关掉了
        #expect(run.poll(at: start) == true)
        #expect(run.panes[1].state == .closed)

        let driver2 = FakeDriver()
        let run2 = try makeRun(folders: ["/a"], driver: driver2)
        driver2.windowGone = true
        #expect(run2.poll(at: start) == true)
        #expect(run2.summary == "1 个终端：0 个 IP 正确，a 已关闭")
    }

    @Test func startPropagatesDriverErrors() {
        let driver = FakeDriver()
        driver.openError = .automationDenied
        #expect(throws: TerminalError.automationDenied) {
            _ = try makeRun(folders: ["/a"], driver: driver)
        }
    }
}

@MainActor
@Suite struct LauncherViewModelTests {
    let home = "/Users/me"

    func makeDefaults() -> UserDefaults {
        let name = "proxy-terminal-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func makeModel(_ defaults: UserDefaults, existing: Set<String> = ["/Users/me", "/w/api", "/w/web"]) -> LauncherViewModel {
        LauncherViewModel(store: PresetStore(defaults: defaults, home: home), home: home,
                          folderExists: { existing.contains($0) })
    }

    @Test func firstUseHasOneDefaultPreset() {
        let model = makeModel(makeDefaults())
        #expect(model.presets.count == 1)
        #expect(model.current.name == "默认")
        #expect(model.current.folders == [home])
        #expect(model.ipProblem == "请先填预期的 IP")
        #expect(!model.canOpen)
    }

    @Test func editsAreSavedImmediately() {
        let defaults = makeDefaults()
        let model = makeModel(defaults)
        model.expectedIP = "1.2.3.4"
        model.setFolder("/w/api", at: 0)
        model.addRow()
        model.setFolder("/w/web", at: 1)
        #expect(model.canOpen)

        let reloaded = makeModel(defaults)
        #expect(reloaded.current.expectedIP == "1.2.3.4")
        #expect(reloaded.current.folders == ["/w/api", "/w/web"])
    }

    @Test func validation() {
        let model = makeModel(makeDefaults())
        model.expectedIP = "1.2.3"
        #expect(model.ipProblem == "IP 格式不对")
        model.expectedIP = "2001:db8::1"
        #expect(model.ipProblem == nil)
        model.setFolder("/gone", at: 0)
        #expect(model.folderProblem(at: 0) == "文件夹不存在")
        #expect(!model.canOpen)
    }

    @Test func rowsStayBetweenOneAndNine() {
        let model = makeModel(makeDefaults())
        model.removeRow(at: 0)
        #expect(model.current.folders.count == 1)
        for _ in 0..<20 { model.addRow() }
        #expect(model.current.folders.count == PaneLayout.maxPanes)
        #expect(!model.canAddRow)
        #expect(model.current.folders.allSatisfy { $0 == home })   // 新行复制上一行
    }

    @Test func presetsCanBeCreatedRenamedDeletedAndRemembered() {
        let defaults = makeDefaults()
        let model = makeModel(defaults)
        model.expectedIP = "1.2.3.4"
        let first = model.selectedID

        model.createPreset(named: "  工作 ")
        #expect(model.presets.count == 2)
        #expect(model.current.name == "工作")
        #expect(model.current.expectedIP == "1.2.3.4")   // 复制自当前这套
        model.expectedIP = "5.6.7.8"
        #expect(model.presets.first { $0.id == first }?.expectedIP == "1.2.3.4")

        model.renameCurrent(to: "公司")
        model.createPreset(named: "   ")                   // 空名字不建
        #expect(model.presets.map(\.name) == ["默认", "公司"])

        // 重新打开时选中上次用的那套
        #expect(makeModel(defaults).current.name == "公司")

        model.deleteCurrent()
        #expect(model.presets.map(\.name) == ["默认"])
        #expect(model.selectedID == first)
        #expect(!model.canDeleteCurrent)
        model.deleteCurrent()
        #expect(model.presets.count == 1)
    }

    @Test func displayPathAbbreviatesHome() {
        let model = makeModel(makeDefaults())
        #expect(model.displayPath("/Users/me") == "~")
        #expect(model.displayPath("/Users/me/work") == "~/work")
        #expect(model.displayPath("/Users/meow") == "/Users/meow")
    }
}
