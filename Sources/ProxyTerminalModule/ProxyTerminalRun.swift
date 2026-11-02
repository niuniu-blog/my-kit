import Foundation

/// 某块终端 IP 核对通过之后，往那块里输入的命令。只有核对通过的块才会被问到；返回 nil 表示什么都不做。
public protocol ProxyPassAction {
    func command(verifiedAddress: String) -> String?
}

public struct NoPassAction: ProxyPassAction {
    public init() {}
    public func command(verifiedAddress: String) -> String? { nil }
}

/// 核对通过后倒计时 5 秒再启动 Claude Code（倒计时中按 Ctrl+C 整行取消，claude 不会启动）。
/// 倒计时结束、启动前在 shell 里再查一次出口 IP，不一致就不启动 ——
/// 防止 MyKit 核对完到 claude 启动之间代理断了或换了线路。
/// 关掉 Claude Code 自己改终端标题，让分屏标题一直是文件夹名。
public struct LaunchClaude: ProxyPassAction {
    public static let countdownSeconds = 5

    public init() {}

    public func command(verifiedAddress: String) -> String? {
        let expected = PaneCommands.shellQuoted(verifiedAddress)
        let seconds = (1...Self.countdownSeconds).reversed().map(String.init).joined(separator: " ")
        // 倒计时不用 \r 原地刷新：分屏窄时一行放不下会折行，\r 只回到折行的开头，屏幕上会留下一堆半截的行
        return "echo '✅ IP 核对通过，\(Self.countdownSeconds) 秒后启动 claude（按 Ctrl+C 取消）'; "
            + "for i in \(seconds); do printf '%s… ' $i; sleep 1; done; echo; "
            + "if [ \"$(curl -s --max-time 10 ip.sb)\" = \(expected) ]; then CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1 claude; "
            + "else echo '❌ 出口 IP 和核对时不一致，已阻止启动 claude'; fi"
    }
}

public enum PaneState: Equatable {
    case waiting
    case passed(String)
    case wrongAddress(String)
    case noAddress
    case timedOut
    case closed

    var isFinished: Bool { self != .waiting }
}

/// 一次「打开代理终端」：开窗口，轮询每块的结果直到全部出结果；
/// 之后对核对通过的块再守 40 秒标题 —— Claude Code 启动后 iTerm2 的「工作组」会把标题改成「聊天」，改回文件夹名。
@MainActor
public final class ProxyTerminalRun {
    public struct Pane: Equatable {
        public let folder: String
        public let title: String
        public let sessionID: String
        public var state: PaneState
        /// 核对通过的时间（守标题用）
        public var passedAt: Date?
    }

    public static let timeout: TimeInterval = 15
    /// 核对通过后守标题多久：倒计时 5 秒 + 再查一次 IP 最多 10 秒 + Claude Code 启动，留足余量
    public static let titleGuard: TimeInterval = 40

    public private(set) var panes: [Pane] = []
    public private(set) var windowID = 0
    /// 全部结束（不用再轮询了）
    public private(set) var isDone = false

    private let preset: TerminalPreset
    private let driver: TerminalDriving
    private let passAction: ProxyPassAction
    private let commands: PaneCommands
    private var startedAt = Date()
    private var summaryTaken = false

    public init(preset: TerminalPreset, driver: TerminalDriving, passAction: ProxyPassAction,
                commands: PaneCommands = PaneCommands()) {
        self.preset = preset
        self.driver = driver
        self.passAction = passAction
        self.commands = commands
    }

    public func start(at now: Date = Date()) throws {
        let titles = PaneLayout.titles(forFolders: preset.folders, aliases: preset.paddedAliases)
        let specs = zip(preset.folders, titles).map { folder, title in
            PaneSpec(title: title, lines: [commands.enterFolder(folder, title: title), commands.checkIP])
        }
        let window = try driver.open(panes: specs)
        windowID = window.windowID
        panes = zip(zip(preset.folders, titles), window.sessionIDs).map { pair, sessionID in
            Pane(folder: pair.0, title: pair.1, sessionID: sessionID, state: .waiting)
        }
        startedAt = now
        driver.showToolbelt()
    }

    /// 每块都出结果了
    public var resultsReady: Bool {
        panes.allSatisfy { $0.state.isFinished }
    }

    /// 全部出结果后返回一次汇总提示，之后返回 nil
    public func takeSummary() -> String? {
        guard resultsReady, !summaryTaken else { return nil }
        summaryTaken = true
        return summary
    }

    /// 读一遍各块：还在等的看结果，刚通过的输入下一步的命令，守标题期内的通过块被改了标题就改回来。
    public func poll(at now: Date = Date()) {
        guard !isDone else { return }
        let snapshots: [String: PaneSnapshot]
        do {
            snapshots = try driver.contents(windowID: windowID)
        } catch {
            // 读不到（窗口被关掉等）：还没出结果的都算关掉了
            for index in panes.indices where !panes[index].state.isFinished {
                panes[index].state = .closed
            }
            isDone = true
            return
        }

        let timedOut = now.timeIntervalSince(startedAt) >= Self.timeout
        var updates: [PaneUpdate] = []
        for index in panes.indices where needsWatching(panes[index], now: now) {
            let pane = panes[index]
            guard let snapshot = snapshots[pane.sessionID] else {
                if !pane.state.isFinished { panes[index].state = .closed }
                continue
            }
            if pane.state == .waiting {
                switch PaneOutputParser.parse(snapshot.text, commands: commands) {
                case .address(let address):
                    panes[index].state = IPAddress.same(address, preset.expectedIP) ? .passed(address) : .wrongAddress(address)
                case .noAddress:
                    panes[index].state = .noAddress
                case .pending:
                    if timedOut { panes[index].state = .timedOut }
                }
            }
            let state = panes[index].state
            let justFinished = pane.state == .waiting && state.isFinished
            // 只有这一次刚核对通过（.passed 只在 IP 与预期一致时才会出现）的块才输入下一步的命令；其余一律不输入
            var typeText: String?
            if justFinished, case .passed(let address) = state {
                typeText = passAction.command(verifiedAddress: address)
                panes[index].passedAt = now
            }
            let title = Self.title(pane.title, state)
            // 标题被别人改了（oh-my-zsh 改成命令名、iTerm2 工作组改成「聊天」）或者状态刚变，才去改
            if justFinished || !snapshot.name.hasPrefix(title) {
                updates.append(PaneUpdate(sessionID: pane.sessionID, title: title,
                                          markFailed: justFinished && !Self.isPassed(state), typeText: typeText))
            }
        }
        try? driver.apply(updates, windowID: windowID)
        isDone = panes.allSatisfy { !needsWatching($0, now: now) }
    }

    /// 还在等结果，或者核对通过还在守标题期内
    private func needsWatching(_ pane: Pane, now: Date) -> Bool {
        if pane.state == .waiting { return true }
        guard let passedAt = pane.passedAt else { return false }
        return now.timeIntervalSince(passedAt) < Self.titleGuard
    }

    /// 全部出结果后弹的提示
    public var summary: String {
        let passed = panes.filter { Self.isPassed($0.state) }.count
        if passed == panes.count {
            return "\(panes.count) 个终端 IP 全部正确"
        }
        let problems = panes.compactMap { pane -> String? in
            switch pane.state {
            case .wrongAddress(let address): return "\(pane.title) 不对（实际 \(address)）"
            case .noAddress: return "\(pane.title) 没拿到 IP"
            case .timedOut: return "\(pane.title) 超时"
            case .closed: return "\(pane.title) 已关闭"
            case .waiting, .passed: return nil
            }
        }
        return "\(panes.count) 个终端：\(passed) 个 IP 正确，" + problems.joined(separator: "、")
    }

    static func isPassed(_ state: PaneState) -> Bool {
        if case .passed = state { return true }
        return false
    }

    static func title(_ base: String, _ state: PaneState) -> String {
        switch state {
        case .waiting, .closed: return base
        case .passed(let address): return "\(base) ✅ \(address)"
        case .wrongAddress(let address): return "\(base) ❌ \(address)"
        case .noAddress: return "\(base) ❌ 没拿到 IP"
        case .timedOut: return "\(base) ❌ 超时"
        }
    }
}
