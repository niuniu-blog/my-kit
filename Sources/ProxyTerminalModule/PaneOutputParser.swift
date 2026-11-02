import Foundation

/// 每块终端里输入的命令，以及从屏幕文字里读出 curl 结果。
///
/// curl 之后再打印一个结束标记 `MYKIT-END-<数字>`。命令行上写的是算式 `$((a+b))`，
/// 只有命令真正执行完，屏幕上才会出现算好的数字 —— 这样不会把还没执行的命令行误当成结果。
public struct PaneCommands: Equatable {
    public let token: Int

    public init(token: Int = Int.random(in: 100_000...999_999)) {
        self.token = token
    }

    public var marker: String { "MYKIT-END-\(token)" }

    /// 第一行：关掉 oh-my-zsh 的自动改标题（否则标题会被改成正在执行的命令和当前路径），
    /// 把标题设成文件夹名（OSC 0 转义序列），再进入文件夹。
    public func enterFolder(_ path: String, title: String) -> String {
        "export DISABLE_AUTO_TITLE=true; printf '\\033]0;%s\\007' \(Self.shellQuoted(title)); cd -- \(Self.shellQuoted(path))"
    }

    /// 第二行：开代理、查出口 IP、打印结束标记。`proxy` 是用户 ~/.zshrc 里的别名，只能在交互式 shell 里用。
    public var checkIP: String {
        let half = token / 2
        return "proxy; curl -s --max-time 10 ip.sb; echo; echo \"MYKIT-END-$((\(half)+\(token - half)))\""
    }

    /// 用单引号包起来给 shell；路径里的单引号写成 '\''。
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum PaneOutput: Equatable {
    /// 还没执行完
    case pending
    /// 拿到了 IP（规范写法）
    case address(String)
    /// 执行完了但没有 IP（curl 失败、代理没开等）
    case noAddress
}

public enum PaneOutputParser {
    public static func parse(_ contents: String, commands: PaneCommands) -> PaneOutput {
        let lines = contents.components(separatedBy: .newlines)
        guard let end = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == commands.marker }) else {
            return .pending
        }
        // 结果夹在命令行（含 "MYKIT-END-$((" 的那一行）和结束标记之间；找不到命令行就只看标记上面几行
        let commandLine = lines[..<end].lastIndex(where: { $0.contains("MYKIT-END-$((") })
        let start = commandLine.map { $0 + 1 } ?? max(0, end - 5)
        let output = lines[start..<end].joined(separator: "\n")
        return IPAddress.firstAddress(in: output).map(PaneOutput.address) ?? .noAddress
    }
}
