import Foundation

/// 正式实现之一：用系统接口把文件移到废纸篓（可以从废纸篓"放回原处"）。
public struct DirectTrasher: FileTrashing {
    public init() {}

    public func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

/// 正式实现之二：请访达把文件移到废纸篓。访达有权限处理属于系统的文件，
/// 需要时由它自己弹出管理员密码框 —— MyKit 不接触密码。
public struct FinderTrasher: PrivilegedTrashing {
    public init() {}

    public func trash(_ urls: [URL]) -> PrivilegedTrashOutcome {
        guard !urls.isEmpty else { return .completed }
        guard let script = NSAppleScript(source: Self.script(for: urls)) else {
            return .failed("无法生成给访达的指令")
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return .completed }

        let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
        switch code {
        case -1743: return .automationDenied            // errAEEventNotPermitted：没有"自动化"授权
        case -128: return .userCancelled                // userCanceledErr
        default:
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "错误 \(code)"
            return .failed(message)
        }
    }

    /// 生成给访达的指令。路径作为字符串字面量传入，先转义反斜杠和双引号；不经过 shell。
    static func script(for urls: [URL]) -> String {
        let files = urls.map { "POSIX file \"\(escape($0.path))\"" }.joined(separator: ", ")
        return "tell application \"Finder\" to delete {\(files)}"
    }

    static func escape(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
