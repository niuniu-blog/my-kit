import Foundation

/// 某块终端 IP 校验通过之后要做的事。用户还没定，第一期是空的；定了以后只换这里。
@MainActor
public protocol ProxyPassAction {
    func run(sessionID: String, folder: String, title: String)
}

public struct NoPassAction: ProxyPassAction {
    nonisolated public init() {}
    public func run(sessionID: String, folder: String, title: String) {}
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

/// 一次「打开代理终端」：开窗口，然后轮询每块的结果直到全部出结果。
@MainActor
public final class ProxyTerminalRun {
    public struct Pane: Equatable {
        public let folder: String
        public let title: String
        public let sessionID: String
        public var state: PaneState
    }

    public static let timeout: TimeInterval = 15

    public private(set) var panes: [Pane] = []
    public private(set) var windowID = 0
    public private(set) var isFinished = false

    private let preset: TerminalPreset
    private let driver: TerminalDriving
    private let passAction: ProxyPassAction
    private let commands: PaneCommands
    private var startedAt = Date()

    public init(preset: TerminalPreset, driver: TerminalDriving, passAction: ProxyPassAction,
                commands: PaneCommands = PaneCommands()) {
        self.preset = preset
        self.driver = driver
        self.passAction = passAction
        self.commands = commands
    }

    public func start(at now: Date = Date()) throws {
        let titles = PaneLayout.titles(forFolders: preset.folders)
        let specs = zip(preset.folders, titles).map { folder, title in
            PaneSpec(title: title, lines: [commands.enterFolder(folder, title: title), commands.checkIP])
        }
        let window = try driver.open(panes: specs)
        windowID = window.windowID
        panes = zip(zip(preset.folders, titles), window.sessionIDs).map { pair, sessionID in
            Pane(folder: pair.0, title: pair.1, sessionID: sessionID, state: .waiting)
        }
        startedAt = now
    }

    /// 读一遍各块的结果。返回 true 表示全部出结果了（之后不用再调）。
    @discardableResult
    public func poll(at now: Date = Date()) -> Bool {
        guard !isFinished else { return true }
        let contents: [String: String]
        do {
            contents = try driver.contents(windowID: windowID)
        } catch {
            // 读不到（窗口被关掉等）：还没出结果的都算关掉了
            for index in panes.indices where !panes[index].state.isFinished {
                panes[index].state = .closed
            }
            return finish()
        }

        let timedOut = now.timeIntervalSince(startedAt) >= Self.timeout
        var updates: [PaneUpdate] = []
        for index in panes.indices where !panes[index].state.isFinished {
            let pane = panes[index]
            guard let text = contents[pane.sessionID] else {
                panes[index].state = .closed
                continue
            }
            switch PaneOutputParser.parse(text, commands: commands) {
            case .address(let address):
                panes[index].state = IPAddress.same(address, preset.expectedIP) ? .passed(address) : .wrongAddress(address)
            case .noAddress:
                panes[index].state = .noAddress
            case .pending:
                if timedOut { panes[index].state = .timedOut }
            }
            // 还在等的也重设一次标题：shell 刚启动时会把标题改成路径
            let state = panes[index].state
            updates.append(PaneUpdate(sessionID: pane.sessionID, title: Self.title(pane.title, state),
                                      markFailed: state.isFinished && !Self.isPassed(state)))
        }
        try? driver.apply(updates, windowID: windowID)

        for pane in panes where updates.contains(where: { $0.sessionID == pane.sessionID }) {
            if case .passed = pane.state {
                passAction.run(sessionID: pane.sessionID, folder: pane.folder, title: pane.title)
            }
        }
        return panes.allSatisfy { $0.state.isFinished } ? finish() : false
    }

    private func finish() -> Bool {
        isFinished = true
        return true
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
