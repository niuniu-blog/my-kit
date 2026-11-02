import AppKit

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
    /// 读窗口里每块的屏幕文字：sessionID → 文字。关掉的块不在结果里。
    func contents(windowID: Int) throws -> [String: String]
    func apply(_ updates: [PaneUpdate], windowID: Int) throws
}

/// 用 AppleScript 控制 iTerm2（与卸载器请访达删文件是同一套机制）。
@MainActor
public struct ITermDriver: TerminalDriving {
    public static let bundleID = "com.googlecode.iterm2"
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

    public func contents(windowID: Int) throws -> [String: String] {
        ITermScripts.parseContents(try run(ITermScripts.contents(windowID: windowID)))
    }

    public func apply(_ updates: [PaneUpdate], windowID: Int) throws {
        guard !updates.isEmpty else { return }
        _ = try run(ITermScripts.apply(updates, windowID: windowID))
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
        // 先上下切出各行（iTerm2 会自动把切出来的块排成一样大），再把有两块的行左右切开
        func splitRows(_ range: Range<Int>) {
            guard range.count > 1 else { return }
            let mid = range.lowerBound + (range.count + 1) / 2
            lines.append("tell p\(heads[range.lowerBound]) to set p\(heads[mid]) to (split horizontally with default profile)")
            splitRows(range.lowerBound..<mid)
            splitRows(mid..<range.upperBound)
        }
        splitRows(0..<rows.count)
        for (row, count) in rows.enumerated() where count == 2 {
            lines.append("tell p\(heads[row]) to set p\(heads[row] + 1) to (split vertically with default profile)")
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

    /// 读窗口里所有块的屏幕文字：块与块之间用 0x1E 隔开，id 和文字之间用 0x1F
    static func contents(windowID: Int) -> String {
        """
        tell application id "\(ITermDriver.bundleID)"
        set out to ""
        repeat with t in tabs of window id \(windowID)
        repeat with s in sessions of t
        set out to out & (id of s) & (character id 31) & (contents of s) & (character id 30)
        end repeat
        end repeat
        return out
        end tell
        """
    }

    static func parseContents(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for record in output.components(separatedBy: recordSeparator) where !record.isEmpty {
            guard let range = record.range(of: fieldSeparator) else { continue }
            result[String(record[..<range.lowerBound])] = String(record[range.upperBound...])
        }
        return result
    }

    /// 改标题；标记失败的把背景往红色调 40%（深色、浅色主题都能看出来）
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
