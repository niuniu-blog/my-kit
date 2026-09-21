import Foundation
import Testing
@testable import UninstallerModule

/// 假的"直接移到废纸篓"：只记录被要求移走的路径，什么都不真的动。
private final class FakeDirectTrasher: FileTrashing, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var errors: [String: Error] = [:]

    var trashedPaths: [String] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func trash(_ url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        if let error = errors[url.lastPathComponent] { throw error }
        recorded.append(url.path)
    }
}

/// 假的访达：记录每次调用收到的那一批路径。
private final class FakePrivilegedTrasher: PrivilegedTrashing, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    var outcome: PrivilegedTrashOutcome = .completed

    var batches: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func trash(_ urls: [URL]) -> PrivilegedTrashOutcome {
        lock.lock(); defer { lock.unlock() }
        recorded.append(urls.map(\.lastPathComponent))
        return outcome
    }
}

@Suite struct TrasherTests {
    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    private let preferences = URL(fileURLWithPath: "/Users/tester/Library/Preferences", isDirectory: true)
    private let daemons = URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true)
    private let permissionDenied = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)

    private var app: AppIdentity {
        AppIdentity(url: URL(fileURLWithPath: "/Users/tester/Applications/Tool.app"), bundleID: "org.example.tool", names: ["Tool"])
    }

    private func item(_ url: URL, size: UInt64 = 100, admin: Bool = false, isApp: Bool = false, service: Bool = false) -> LeftoverItem {
        LeftoverItem(url: url, category: "测试", confidence: .certain, needsAdmin: admin,
                     isAppBundle: isApp, isBackgroundService: service, sizeBytes: size)
    }

    private func makeTrasher(
        _ direct: FakeDirectTrasher, _ privileged: FakePrivilegedTrasher, remaining: Set<String> = []
    ) -> Trasher {
        Trasher(direct: direct, privileged: privileged, scanRoots: [preferences, daemons], home: home,
                stillExists: { remaining.contains($0.lastPathComponent) })
    }

    @Test func movesAllowedItemsDirectlyAndSumsFreedBytes() {
        let direct = FakeDirectTrasher()
        let privileged = FakePrivilegedTrasher()
        let items = [
            item(preferences.appendingPathComponent("org.example.tool.plist"), size: 300),
            item(preferences.appendingPathComponent("org.example.tool.helper.plist"), size: 200),
        ]

        let report = makeTrasher(direct, privileged).run(items: items, app: app)

        #expect(direct.trashedPaths == items.map(\.url.path))
        #expect(privileged.batches.isEmpty)
        #expect(report.succeeded == items)
        #expect(report.failed.isEmpty)
        #expect(report.freedBytes == 500)
        #expect(report.summary == "已移到废纸篓 2 项，释放 1 KB")
        #expect(!report.removedAppBundle)
    }

    @Test func revalidationRejectsPathsOutsideTheAllowedPlaces() {
        let direct = FakeDirectTrasher()
        let items = [
            item(URL(fileURLWithPath: "/Users/tester/Documents/report.txt")),
            item(preferences),                                                              // 扫描位置本身
            item(preferences.appendingPathComponent("../../.ssh")),
            item(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")),
            item(preferences.appendingPathComponent("org.example.tool.plist")),
        ]

        let report = makeTrasher(direct, FakePrivilegedTrasher()).run(items: items, app: app)

        #expect(direct.trashedPaths == ["/Users/tester/Library/Preferences/org.example.tool.plist"])
        #expect(report.failed.map(\.reason) == Array(repeating: "路径不在允许范围内", count: 4))
        #expect(report.summary == "已移到废纸篓 1 项，释放 1 KB；4 项没有移走")
    }

    @Test func permissionFailuresGoToFinderInOneBatch() {
        let direct = FakeDirectTrasher()
        direct.errors = ["org.example.tool.daemon.plist": permissionDenied, "org.example.tool.agent.plist": permissionDenied]
        let privileged = FakePrivilegedTrasher()
        let items = [
            item(daemons.appendingPathComponent("org.example.tool.daemon.plist"), admin: true, service: true),
            item(preferences.appendingPathComponent("org.example.tool.plist")),
            item(daemons.appendingPathComponent("org.example.tool.agent.plist"), admin: true, service: true),
        ]

        let report = makeTrasher(direct, privileged).run(items: items, app: app)

        #expect(privileged.batches == [["org.example.tool.daemon.plist", "org.example.tool.agent.plist"]])   // 只调用一次
        #expect(report.succeeded.count == 3)
        #expect(report.touchedBackgroundServices)
        #expect(!report.automationDenied)
    }

    @Test func itemsFinderLeftBehindAreReportedAsFailed() {
        let direct = FakeDirectTrasher()
        direct.errors = ["a.plist": permissionDenied, "b.plist": permissionDenied]
        let items = [item(daemons.appendingPathComponent("a.plist")), item(daemons.appendingPathComponent("b.plist"))]

        let report = makeTrasher(direct, FakePrivilegedTrasher(), remaining: ["b.plist"]).run(items: items, app: app)

        #expect(report.succeeded.map(\.url.lastPathComponent) == ["a.plist"])
        #expect(report.failed.map(\.reason) == ["访达没有移走它（可能取消了密码输入）"])
    }

    @Test func automationDeniedAndCancelledPasswordGiveClearReasons() {
        let direct = FakeDirectTrasher()
        direct.errors = ["a.plist": permissionDenied]
        let items = [item(daemons.appendingPathComponent("a.plist"))]

        let denied = FakePrivilegedTrasher()
        denied.outcome = .automationDenied
        let deniedReport = makeTrasher(direct, denied).run(items: items, app: app)
        #expect(deniedReport.automationDenied)
        #expect(deniedReport.failed.map(\.reason) == ["需要管理员权限，但 MyKit 没有获得控制访达的授权"])

        let cancelled = FakePrivilegedTrasher()
        cancelled.outcome = .userCancelled
        let cancelledReport = makeTrasher(direct, cancelled).run(items: items, app: app)
        #expect(!cancelledReport.automationDenied)
        #expect(cancelledReport.failed.map(\.reason) == ["需要管理员密码，你取消了输入"])

        let broken = FakePrivilegedTrasher()
        broken.outcome = .failed("Finder 出错了")
        #expect(makeTrasher(direct, broken).run(items: items, app: app).failed.map(\.reason) == ["访达没能移走它：Finder 出错了"])
    }

    @Test func appManagementHintWhenAnUnexpectedPermissionWallBlocksTheApp() throws {
        let temp = try TempDir()
        let fakeHome = try temp.makeDirectory("home")
        let appURL = try temp.makeApp("home/Applications/Tool.app", bundleID: "org.example.tool")
        let identity = try #require(AppIdentity(appURL: appURL))
        let direct = FakeDirectTrasher()
        direct.errors = ["Tool.app": NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))]
        let privileged = FakePrivilegedTrasher()
        privileged.outcome = .automationDenied
        let trasher = Trasher(direct: direct, privileged: privileged, scanRoots: [], home: fakeHome, stillExists: { _ in true })

        let report = trasher.run(items: [item(appURL, admin: false, isApp: true)], app: identity)

        #expect(report.appManagementBlocked)
        #expect(report.summary == "没有移走任何项")
        #expect(FileManager.default.fileExists(atPath: appURL.path))                     // 假执行器：文件原封不动
    }

    @Test func appMovedByFinderAfterAPermissionErrorIsASuccess() throws {
        let temp = try TempDir()
        let fakeHome = try temp.makeDirectory("home")
        let appURL = try temp.makeApp("home/Applications/Tool.app", bundleID: "org.example.tool")
        let identity = try #require(AppIdentity(appURL: appURL))
        let direct = FakeDirectTrasher()
        direct.errors = ["Tool.app": permissionDenied]
        let trasher = Trasher(direct: direct, privileged: FakePrivilegedTrasher(), scanRoots: [], home: fakeHome,
                              stillExists: { _ in false })

        let report = trasher.run(items: [item(appURL, admin: true, isApp: true)], app: identity)

        #expect(report.removedAppBundle)
        #expect(!report.appManagementBlocked)
    }

    @Test func otherErrorsAreReportedWithoutBotheringFinder() {
        let direct = FakeDirectTrasher()
        direct.errors = [
            "gone.plist": NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError),
            "odd.plist": NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "磁盘出错"]),
        ]
        let privileged = FakePrivilegedTrasher()
        let items = [item(preferences.appendingPathComponent("gone.plist")), item(preferences.appendingPathComponent("odd.plist"))]

        let report = makeTrasher(direct, privileged).run(items: items, app: app)

        #expect(privileged.batches.isEmpty)
        #expect(report.failed.map(\.reason) == ["文件已经不存在", "磁盘出错"])
    }

    @Test func emptyInputGivesAnEmptyReport() {
        let report = makeTrasher(FakeDirectTrasher(), FakePrivilegedTrasher()).run(items: [], app: app)
        #expect(report.summary == "没有需要移走的项")
        #expect(report.freedBytes == 0)
    }

    @Test func finderScriptEscapesQuotesAndBackslashes() {
        let urls = [
            URL(fileURLWithPath: "/Library/LaunchDaemons/org.example.tool.plist"),
            URL(fileURLWithPath: "/Library/Application Support/We\"ird\\Name"),
        ]
        let script = FinderTrasher.script(for: urls)
        #expect(script == "tell application \"Finder\" to delete {POSIX file \"/Library/LaunchDaemons/org.example.tool.plist\", POSIX file \"/Library/Application Support/We\\\"ird\\\\Name\"}")
    }
}

/// 设计文档 §4.3：模块的正式代码里不允许出现任何永久删除，也不允许调用外部命令。
@Suite struct NoPermanentDeleteTests {
    @Test func productionSourcesContainNoDestructiveCalls() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let sources = testFile
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/UninstallerModule", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count >= 5)

        let forbidden = [
            "removeItem", "unlink(", "rmdir(", "Process(", "/bin/rm", "performFileOperation",
            "recycle(", "empty trash", "empty the trash", "NSTask", "popen(", "forceTerminate",
        ]
        // C 的 system() 调用；前面带点的（比如 SwiftUI 的 .font(.system(size:))）不算
        let systemCall = try NSRegularExpression(pattern: "(?<![.\\w])system\\(")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                #expect(!text.contains(token), "\(file.lastPathComponent) 里出现了 \(token)")
            }
            let range = NSRange(text.startIndex..., in: text)
            #expect(systemCall.firstMatch(in: text, range: range) == nil, "\(file.lastPathComponent) 里调用了 system()")
        }

        // 移走文件只允许这两种写法，而且各自只出现在 SystemTrashers.swift 里
        for file in files where file.lastPathComponent != "SystemTrashers.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("trashItem("), "\(file.lastPathComponent)")
            #expect(!text.contains("NSAppleScript("), "\(file.lastPathComponent)")
        }
    }
}
