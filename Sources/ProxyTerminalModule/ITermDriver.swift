import AppKit
import ApplicationServices
import os

public enum TerminalError: Error, Equatable {
    /// 没装 iTerm2
    case notInstalled
    /// 用户没允许 MyKit 控制 iTerm2（系统设置 → 隐私与安全性 → 自动化）
    case automationDenied
    /// 窗口已经被关掉了
    case windowClosed
    case failed(String)
}

public struct OpenedWindow: Equatable {
    public let windowID: Int
    /// 按块的顺序（从上到下、从左到右）
    public let sessionIDs: [String]
}

public struct PaneUpdate: Equatable {
    public let sessionID: String
    public let title: String
    /// 把背景染红
    public let markFailed: Bool
    /// 改完标题后往这块里输入的命令（只有核对通过的块才有）
    public let typeText: String?

    public init(sessionID: String, title: String, markFailed: Bool, typeText: String? = nil) {
        self.sessionID = sessionID
        self.title = title
        self.markFailed = markFailed
        self.typeText = typeText
    }
}

/// 读到的一块终端：标题（iTerm2 显示的，带 " (claude)" 之类的后缀）和屏幕文字
public struct PaneSnapshot: Equatable {
    public let name: String
    public let text: String

    public init(name: String, text: String) {
        self.name = name
        self.text = text
    }
}

/// 一块终端的打开参数
public struct PaneSpec: Equatable {
    public let title: String
    public let lines: [String]
}

/// 控制终端的接口。正式实现是 ITermDriver，测试里换成假的。
@MainActor
public protocol TerminalDriving {
    func open(panes: [PaneSpec]) throws -> OpenedWindow
    /// 读窗口里每块的标题和屏幕文字：sessionID → 内容。关掉的块不在结果里。
    func contents(windowID: Int) throws -> [String: PaneSnapshot]
    func apply(_ updates: [PaneUpdate], windowID: Int) throws
    /// 在刚打开的窗口里显示 iTerm2 的工具箱（右侧「会话状态」等）。尽力而为，失败不报错。
    func showToolbelt()
}

/// 用 AppleScript 控制 iTerm2（与卸载器请访达删文件是同一套机制）。
@MainActor
public struct ITermDriver: TerminalDriving {
    nonisolated public static let bundleID = "com.googlecode.iterm2"
    nonisolated public init() {}

    public static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    public func open(panes: [PaneSpec]) throws -> OpenedWindow {
        let output = try run(ITermScripts.open(panes: panes))
        let parts = output.components(separatedBy: "\n")
        guard let windowID = Int(parts.first ?? ""), parts.count == panes.count + 1 else {
            throw TerminalError.failed("iTerm2 返回了看不懂的结果")
        }
        return OpenedWindow(windowID: windowID, sessionIDs: Array(parts.dropFirst()))
    }

    public func contents(windowID: Int) throws -> [String: PaneSnapshot] {
        ITermScripts.parseContents(try run(ITermScripts.contents(windowID: windowID)))
    }

    public func apply(_ updates: [PaneUpdate], windowID: Int) throws {
        guard !updates.isEmpty else { return }
        _ = try run(ITermScripts.apply(updates, windowID: windowID))
    }

    /// iTerm2 菜单「工具箱 → 显示工具箱」的中文 / 英文标题
    static let showToolbeltTitles: Set<String> = ["显示工具箱", "Show Toolbelt"]
    private static let log = Logger(subsystem: "com.imiros.mykit", category: "proxyTerminal")

    /// iTerm2 没有显示工具箱的 AppleScript，只能通过辅助功能接口点它的菜单项（MyKit 本来就有辅助功能授权）。
    /// 这个菜单项是"开 / 关"切换，且读不到勾选状态，所以先看最前面的窗口里有没有工具箱
    /// （有工具箱的窗口直接带一个分栏视图 AXSplitGroup）—— 已经有了就不点，绝不会把它关掉。
    /// 窗口刚建好时 iTerm2 可能还没到最前面、菜单项还不可点，每 0.2 秒再试，最多 10 次。
    public func showToolbelt() {
        Self.attemptShowToolbelt(remaining: 10)
    }

    private static func attemptShowToolbelt(remaining: Int) {
        guard remaining > 0 else {
            log.error("工具箱：重试用完仍未能点菜单")
            return
        }
        guard AXIsProcessTrusted() else {
            log.error("工具箱：没有辅助功能授权")
            return
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        let window: AXUIElement? = axAttribute(element, kAXFocusedWindowAttribute)
        let menuBar: AXUIElement? = axAttribute(element, kAXMenuBarAttribute)
        let item = menuBar.flatMap { findMenuItem(in: $0, titles: showToolbeltTitles, depth: 0) }
        let enabled: Bool? = item.flatMap { axAttribute($0, kAXEnabledAttribute) }
        guard app.isActive, let window, let item, enabled == true else {
            log.info("工具箱：还不能点（active=\(app.isActive) window=\(window != nil) item=\(item != nil) enabled=\(String(describing: enabled), privacy: .public)），剩 \(remaining - 1) 次")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                MainActor.assumeIsolated { attemptShowToolbelt(remaining: remaining - 1) }
            }
            return
        }
        let children: [AXUIElement] = axAttribute(window, kAXChildrenAttribute) ?? []
        let roles = children.compactMap { axAttribute($0, kAXRoleAttribute) as String? }
        let hasToolbelt = roles.contains(kAXSplitGroupRole as String)
        if hasToolbelt {
            log.info("工具箱：窗口里已经有了，不点（\(roles.joined(separator: ","), privacy: .public)）")
        } else {
            let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
            log.info("工具箱：点了「显示工具箱」，结果 \(result.rawValue)")
        }
    }

    private static func axAttribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// 菜单层级：菜单栏 → 菜单栏项 → 菜单 → 「工具箱」→ 子菜单 →「显示工具箱」，所以要找到第 5 层
    private static func findMenuItem(in element: AXUIElement, titles: Set<String>, depth: Int) -> AXUIElement? {
        guard depth < 6 else { return nil }
        for child in axAttribute(element, kAXChildrenAttribute) as [AXUIElement]? ?? [] {
            if let title: String = axAttribute(child, kAXTitleAttribute), titles.contains(title) {
                return child
            }
            if let found = findMenuItem(in: child, titles: titles, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    private func run(_ source: String) throws -> String {
        guard Self.isInstalled else { throw TerminalError.notInstalled }
        guard let script = NSAppleScript(source: source) else {
            throw TerminalError.failed("无法生成给 iTerm2 的指令")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return result.stringValue ?? "" }

        let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
        switch code {
        case -1743: throw TerminalError.automationDenied   // errAEEventNotPermitted
        case -1728: throw TerminalError.windowClosed       // errAENoSuchObject：窗口没了
        default:
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "错误 \(code)"
            throw TerminalError.failed(message)
        }
    }
}

/// 生成给 iTerm2 的 AppleScript。纯文字处理，可单元测试。
enum ITermScripts {
    /// 开窗口、切块、设标题、输入命令。返回 "窗口 id\n第 1 块 id\n第 2 块 id…"。
    static func open(panes: [PaneSpec]) -> String {
        let rows = PaneLayout.rows(count: panes.count)
        let heads = rows.indices.map { rows[..<$0].reduce(0, +) }   // 每行第一块的序号
        var lines = [
            "tell application id \"\(ITermDriver.bundleID)\"",
            "activate",
            "set w to (create window with default profile)",
            "set p0 to current session of w",
        ]
        // 先上下切出各行，再把每行左右切开（iTerm2 会自动把同一层切出来的块排成一样大）。
        // 对半递归地切：被切的块留在上/左，新块在下/右，所以序号从上到下、从左到右递增。
        func split(_ ids: [Int], _ direction: String) {
            guard ids.count > 1 else { return }
            let mid = (ids.count + 1) / 2
            lines.append("tell p\(ids[0]) to set p\(ids[mid]) to (split \(direction) with default profile)")
            split(Array(ids[..<mid]), direction)
            split(Array(ids[mid...]), direction)
        }
        split(heads, "horizontally")
        for (row, count) in rows.enumerated() {
            split(Array(heads[row]..<(heads[row] + count)), "vertically")
        }
        for (index, pane) in panes.enumerated() {
            lines.append("tell p\(index)")
            lines.append("set name to \(quoted(pane.title))")
            for text in pane.lines {
                lines.append("write text \(quoted(text))")
            }
            lines.append("end tell")
        }
        let ids = panes.indices.map { "(id of p\($0))" }.joined(separator: " & linefeed & ")
        lines.append("return ((id of w) as text) & linefeed & \(ids)")
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    static let recordSeparator = "\u{1E}"
    static let fieldSeparator = "\u{1F}"

    /// 读窗口里所有块的标题和屏幕文字：块与块之间用 0x1E 隔开，id、标题、文字之间用 0x1F
    static func contents(windowID: Int) -> String {
        """
        tell application id "\(ITermDriver.bundleID)"
        set out to ""
        repeat with t in tabs of window id \(windowID)
        repeat with s in sessions of t
        set out to out & (id of s) & (character id 31) & (name of s) & (character id 31) & (contents of s) & (character id 30)
        end repeat
        end repeat
        return out
        end tell
        """
    }

    static func parseContents(_ output: String) -> [String: PaneSnapshot] {
        var result: [String: PaneSnapshot] = [:]
        for record in output.components(separatedBy: recordSeparator) where !record.isEmpty {
            let fields = record.split(separator: Character(fieldSeparator), maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }
            result[String(fields[0])] = PaneSnapshot(name: String(fields[1]), text: String(fields[2]))
        }
        return result
    }

    /// 改标题；标记失败的把背景往红色调 40%（深色、浅色主题都能看出来）；需要时输入下一步的命令
    static func apply(_ updates: [PaneUpdate], windowID: Int) -> String {
        var lines = [
            "tell application id \"\(ITermDriver.bundleID)\"",
            "repeat with t in tabs of window id \(windowID)",
            "repeat with s in sessions of t",
            "set sid to id of s",
        ]
        for update in updates {
            lines.append("if sid is \(quoted(update.sessionID)) then")
            lines.append("set name of s to \(quoted(update.title))")
            if update.markFailed {
                lines.append("set c to background color of s")
                lines.append("set background color of s to {((item 1 of c) * 0.6 + 26214) as integer, ((item 2 of c) * 0.6) as integer, ((item 3 of c) * 0.6) as integer}")
            }
            if let text = update.typeText {
                lines.append("tell s to write text \(quoted(text))")
            }
            lines.append("end if")
        }
        lines += ["end repeat", "end repeat", "end tell"]
        return lines.joined(separator: "\n")
    }

    /// AppleScript 字符串字面量：转义反斜杠和双引号
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
