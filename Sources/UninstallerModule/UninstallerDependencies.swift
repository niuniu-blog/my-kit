import AppKit
import Foundation

/// 视图模型用到的全部"会碰系统"的操作。正式运行用 live()；测试里全部换成假的。
public struct UninstallerDependencies {
    public var listApps: @Sendable () -> InstalledAppList
    public var scanLeftovers: @Sendable (AppIdentity, Set<String>, @Sendable () -> Bool) -> LeftoverScanResult
    public var sizeOf: @Sendable (URL, @Sendable () -> Bool) -> UInt64?
    /// 拖进来的 .app → 列表里的一行；读不出软件信息时返回 nil
    public var makeApp: @Sendable (URL) -> InstalledApp?
    public var isProtected: @Sendable (URL, String?) -> Bool
    public var isRunning: @MainActor (AppIdentity) -> Bool
    /// 请软件正常退出并等它退出；返回是否已经退出
    public var quit: @MainActor (AppIdentity) async -> Bool
    public var trash: @Sendable ([LeftoverItem], AppIdentity) -> TrashReport

    public init(
        listApps: @escaping @Sendable () -> InstalledAppList,
        scanLeftovers: @escaping @Sendable (AppIdentity, Set<String>, @Sendable () -> Bool) -> LeftoverScanResult,
        sizeOf: @escaping @Sendable (URL, @Sendable () -> Bool) -> UInt64?,
        makeApp: @escaping @Sendable (URL) -> InstalledApp?,
        isProtected: @escaping @Sendable (URL, String?) -> Bool,
        isRunning: @escaping @MainActor (AppIdentity) -> Bool,
        quit: @escaping @MainActor (AppIdentity) async -> Bool,
        trash: @escaping @Sendable ([LeftoverItem], AppIdentity) -> TrashReport
    ) {
        self.listApps = listApps
        self.scanLeftovers = scanLeftovers
        self.sizeOf = sizeOf
        self.makeApp = makeApp
        self.isProtected = isProtected
        self.isRunning = isRunning
        self.quit = quit
        self.trash = trash
    }

    public static func live() -> UninstallerDependencies {
        let scanner = LeftoverScanner.standard()
        let trasher = Trasher(
            direct: DirectTrasher(), privileged: FinderTrasher(),
            scanRoots: scanner.scanRoots, home: scanner.home)
        return UninstallerDependencies(
            listApps: { InstalledAppScanner.standard().scan() },
            scanLeftovers: { identity, others, isCancelled in
                scanner.scan(identity: identity, otherBundleIDs: others, isCancelled: isCancelled)
            },
            sizeOf: { url, isCancelled in SizeCalculator.allocatedSize(of: url, isCancelled: isCancelled) },
            makeApp: { InstalledApp(appURL: $0) },
            isProtected: { ProtectionRules.isProtectedApp(url: $0, bundleID: $1) },
            isRunning: { RunningAppControl.isRunning($0) },
            quit: { await RunningAppControl.quit($0) },
            trash: { items, identity in trasher.run(items: items, app: identity) }
        )
    }
}

/// 目标软件是否正在运行、以及请它正常退出。只用正常退出，从不强制结束。
@MainActor
enum RunningAppControl {
    static func instances(of identity: AppIdentity) -> [NSRunningApplication] {
        let targetPath = ProtectionRules.normalizedPath(identity.url)
        return NSWorkspace.shared.runningApplications.filter { app in
            if let bundleID = identity.bundleID, app.bundleIdentifier == bundleID { return true }
            if let url = app.bundleURL, ProtectionRules.normalizedPath(url) == targetPath { return true }
            return false
        }
    }

    static func isRunning(_ identity: AppIdentity) -> Bool {
        !instances(of: identity).isEmpty
    }

    /// 最多等 timeout 秒。
    static func quit(_ identity: AppIdentity, timeout: TimeInterval = 5) async -> Bool {
        for app in instances(of: identity) {
            app.terminate()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isRunning(identity) { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return !isRunning(identity)
    }
}

/// 线程安全的取消标记：主线程置位，后台的扫描 / 大小计算轮询它。
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
    }
}

/// 把完整路径缩短成给人看的样子："~/Library/Caches/…"
public enum PathDisplay {
    public static func abbreviated(_ url: URL, home: URL) -> String {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }

    /// 所在文件夹（清单里每一行显示的位置）
    public static func location(of url: URL, home: URL) -> String {
        abbreviated(url.deletingLastPathComponent(), home: home)
    }
}
