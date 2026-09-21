import Foundation

/// 一个要检查的目录。只看它的一级子项：判断的是子项的名字。
public struct ScanLocation: Equatable, Sendable {
    public enum Kind: Sendable {
        /// 里面的东西按 bundle id 命名（偏好设置、容器、启动项……）
        case byIdentifier
        /// 里面的东西按软件名或 bundle id 建文件夹（应用数据、缓存、日志……）
        case byName
        /// 崩溃报告：文件名以"软件名_日期"开头
        case crashReports
        /// 隐藏文件（主目录下以 . 开头的项，以及 ~/.config 之类目录里的项）
        case hidden
    }

    public let url: URL
    /// 显示给用户的中文类别名
    public let category: String
    public let kind: Kind
    /// 系统级目录（通常需要管理员密码）
    public let isSystemLevel: Bool
    /// 后台服务 / 特权帮助程序：移走后要重启电脑才会完全停止
    public let isBackgroundService: Bool

    public init(url: URL, category: String, kind: Kind, isSystemLevel: Bool = false, isBackgroundService: Bool = false) {
        self.url = url
        self.category = category
        self.kind = kind
        self.isSystemLevel = isSystemLevel
        self.isBackgroundService = isBackgroundService
    }

    /// 正式运行时的全部位置。
    public static func standard() -> [ScanLocation] {
        all(
            home: FileManager.default.homeDirectoryForCurrentUser,
            systemRoot: URL(fileURLWithPath: "/", isDirectory: true),
            userCacheDirectory: darwinUserDirectory(_CS_DARWIN_USER_CACHE_DIR),
            userTempDirectory: darwinUserDirectory(_CS_DARWIN_USER_TEMP_DIR)
        )
    }

    /// home / systemRoot 可注入：测试里全部指向临时目录。
    public static func all(home: URL, systemRoot: URL, userCacheDirectory: URL?, userTempDirectory: URL?) -> [ScanLocation] {
        func userLevel(_ path: String, _ category: String, _ kind: Kind, service: Bool = false) -> ScanLocation {
            ScanLocation(url: home.appendingPathComponent(path, isDirectory: true), category: category, kind: kind,
                         isBackgroundService: service)
        }
        func systemLevel(_ path: String, _ category: String, _ kind: Kind, service: Bool = false) -> ScanLocation {
            ScanLocation(url: systemRoot.appendingPathComponent(path, isDirectory: true), category: category, kind: kind,
                         isSystemLevel: true, isBackgroundService: service)
        }

        var locations: [ScanLocation] = [
            userLevel("Library/Application Support", "应用数据", .byName),
            userLevel("Library/Caches", "缓存", .byName),
            userLevel("Library/Preferences", "偏好设置", .byIdentifier),
            userLevel("Library/Preferences/ByHost", "偏好设置", .byIdentifier),
            userLevel("Library/Logs", "日志", .byName),
            userLevel("Library/Logs/DiagnosticReports", "崩溃报告", .crashReports),
            userLevel("Library/Saved Application State", "窗口状态", .byName),
            userLevel("Library/Containers", "容器数据", .byIdentifier),
            userLevel("Library/Group Containers", "容器数据", .byIdentifier),
            userLevel("Library/Application Scripts", "应用脚本", .byName),
            userLevel("Library/HTTPStorages", "网络数据", .byName),
            userLevel("Library/Cookies", "网络数据", .byIdentifier),
            userLevel("Library/WebKit", "网络数据", .byName),
            userLevel("Library/LaunchAgents", "登录时启动项", .byIdentifier, service: true),
            userLevel("Library/Autosave Information", "自动保存", .byName),
            userLevel("Library/Services", "扩展", .byIdentifier),
            userLevel("Library/PreferencePanes", "扩展", .byIdentifier),
            userLevel("Library/Internet Plug-Ins", "扩展", .byIdentifier),
        ]
        if let userCacheDirectory {
            locations.append(ScanLocation(url: userCacheDirectory, category: "系统临时缓存", kind: .byName))
        }
        if let userTempDirectory {
            locations.append(ScanLocation(url: userTempDirectory, category: "系统临时缓存", kind: .byName))
        }
        locations += [
            ScanLocation(url: home, category: "隐藏文件", kind: .hidden),
            userLevel(".config", "隐藏文件", .hidden),
            userLevel(".cache", "隐藏文件", .hidden),
            userLevel(".local/share", "隐藏文件", .hidden),

            systemLevel("Library/Application Support", "系统级数据", .byName),
            systemLevel("Library/Caches", "系统级数据", .byName),
            systemLevel("Library/Logs", "系统级数据", .byName),
            systemLevel("Library/Preferences", "系统级数据", .byIdentifier),
            systemLevel("Library/LaunchAgents", "后台服务", .byIdentifier, service: true),
            systemLevel("Library/LaunchDaemons", "后台服务", .byIdentifier, service: true),
            systemLevel("Library/PrivilegedHelperTools", "特权帮助程序", .byIdentifier, service: true),
            systemLevel("private/var/db/receipts", "安装记录", .byIdentifier),
        ]
        return locations
    }

    /// 每个用户专属的缓存 / 临时目录（/var/folders/xx/…/C 和 …/T），平时看不到。
    static func darwinUserDirectory(_ name: Int32) -> URL? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(name, &buffer, buffer.count)
        guard length > 0, length <= buffer.count else { return nil }
        let path = String(cString: buffer)
        return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
    }
}
