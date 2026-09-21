import Foundation

/// 直接把一个文件 / 文件夹移到废纸篓（当前用户有权限时）。
public protocol FileTrashing: Sendable {
    func trash(_ url: URL) throws
}

/// 需要管理员权限的那一批：一次调用交给有权限的执行者（正式实现是访达）。
public protocol PrivilegedTrashing: Sendable {
    func trash(_ urls: [URL]) -> PrivilegedTrashOutcome
}

public enum PrivilegedTrashOutcome: Equatable, Sendable {
    /// 请求已被执行（具体每一项是否真的被移走，由调用方再核对）
    case completed
    /// 用户没有允许 MyKit 控制访达
    case automationDenied
    /// 用户在密码框里点了取消
    case userCancelled
    case failed(String)
}

public struct TrashFailure: Equatable, Sendable, Identifiable {
    public let item: LeftoverItem
    public let reason: String
    public var id: String { item.id }
}

public struct TrashReport: Equatable, Sendable {
    public var succeeded: [LeftoverItem] = []
    public var failed: [TrashFailure] = []
    /// 软件本体被系统的"App 管理"保护拦住了：要引导用户去系统设置里放行
    public var appManagementBlocked = false
    /// 用户没有允许 MyKit 控制访达：要引导用户去"自动化"里放行
    public var automationDenied = false

    public init() {}

    public var freedBytes: UInt64 { succeeded.reduce(0) { $0 + ($1.sizeBytes ?? 0) } }
    public var touchedBackgroundServices: Bool { succeeded.contains { $0.isBackgroundService } }
    public var removedAppBundle: Bool { succeeded.contains { $0.isAppBundle } }

    /// 结果页顶部的一句话
    public var summary: String {
        if succeeded.isEmpty {
            return failed.isEmpty ? "没有需要移走的项" : "没有移走任何项"
        }
        var text = "已移到废纸篓 \(succeeded.count) 项，释放 \(SizeCalculator.format(freedBytes))"
        if !failed.isEmpty { text += "；\(failed.count) 项没有移走" }
        return text
    }
}

/// 执行"移到废纸篓"。只有两条路：直接移；权限不够的攒成一批交给有权限的执行者。
/// 这里没有、也不允许有任何永久删除。
public struct Trasher: Sendable {
    private let direct: FileTrashing
    private let privileged: PrivilegedTrashing
    private let scanRoots: [URL]
    private let home: URL
    private let stillExists: @Sendable (URL) -> Bool

    public init(
        direct: FileTrashing,
        privileged: PrivilegedTrashing,
        scanRoots: [URL],
        home: URL,
        stillExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) {
        self.direct = direct
        self.privileged = privileged
        self.scanRoots = scanRoots
        self.home = home
        self.stillExists = stillExists
    }

    public func run(items: [LeftoverItem], app: AppIdentity) -> TrashReport {
        var report = TrashReport()
        var needingPrivileges: [LeftoverItem] = []
        var appBundleHitPermissionWall = false

        for item in items {
            // 1. 动手前的最后一次复核
            let check = ProtectionRules.checkRemoval(
                of: item.url, appURL: app.url, appBundleID: app.bundleID, scanRoots: scanRoots, home: home)
            if case .rejected(let reason) = check {
                report.failed.append(TrashFailure(item: item, reason: reason))
                continue
            }
            // 2. 直接移
            do {
                try direct.trash(item.url)
                report.succeeded.append(item)
            } catch {
                if Self.isPermissionError(error) {
                    needingPrivileges.append(item)
                    if item.isAppBundle, !item.needsAdmin { appBundleHitPermissionWall = true }
                } else if Self.isMissingFileError(error) {
                    report.failed.append(TrashFailure(item: item, reason: "文件已经不存在"))
                } else {
                    report.failed.append(TrashFailure(item: item, reason: error.localizedDescription))
                }
            }
        }

        // 3. 权限不够的：合成一批，只麻烦用户输一次密码
        if !needingPrivileges.isEmpty {
            let outcome = privileged.trash(needingPrivileges.map(\.url))
            for item in needingPrivileges {
                switch outcome {
                case .completed:
                    if stillExists(item.url) {
                        report.failed.append(TrashFailure(item: item, reason: "访达没有移走它（可能取消了密码输入）"))
                    } else {
                        report.succeeded.append(item)
                    }
                case .automationDenied:
                    report.automationDenied = true
                    report.failed.append(TrashFailure(item: item, reason: "需要管理员权限，但 MyKit 没有获得控制访达的授权"))
                case .userCancelled:
                    report.failed.append(TrashFailure(item: item, reason: "需要管理员密码，你取消了输入"))
                case .failed(let message):
                    report.failed.append(TrashFailure(item: item, reason: "访达没能移走它：\(message)"))
                }
            }
        }

        if appBundleHitPermissionWall, report.failed.contains(where: { $0.item.isAppBundle }) {
            report.appManagementBlocked = true
        }
        return report
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileReadNoPermissionError
        }
        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == Int(EACCES) || nsError.code == Int(EPERM)
        }
        return false
    }

    static func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError
        }
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT)
    }
}
