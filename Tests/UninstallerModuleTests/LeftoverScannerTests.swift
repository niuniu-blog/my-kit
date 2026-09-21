import Foundation
import Testing
@testable import UninstallerModule

@Suite struct LeftoverScannerTests {
    /// 在临时目录里搭一个假的主目录和假的系统根目录。
    private struct World {
        let temp: TempDir
        let home: URL
        let systemRoot: URL
        let appURL: URL
        let identity: AppIdentity
        let scanner: LeftoverScanner

        init() throws {
            temp = try TempDir()
            home = try temp.makeDirectory("home")
            systemRoot = try temp.makeDirectory("root")
            appURL = try temp.makeApp("root/Applications/Tool.app", bundleID: "org.example.tool", name: "Tool Pro")
            identity = try #require(AppIdentity(appURL: appURL))
            let cache = try temp.makeDirectory("var/C")
            scanner = LeftoverScanner(
                locations: ScanLocation.all(home: home, systemRoot: systemRoot, userCacheDirectory: cache, userTempDirectory: nil),
                home: home)
        }
    }

    private func names(_ result: LeftoverScanResult, _ confidence: Confidence) -> Set<String> {
        Set(result.items.filter { $0.confidence == confidence && !$0.isAppBundle }.map(\.url.lastPathComponent))
    }

    @Test func appBundleIsAlwaysTheFirstItem() throws {
        let world = try World()
        let result = world.scanner.scan(identity: world.identity)

        let first = try #require(result.items.first)
        #expect(first.isAppBundle)
        #expect(first.url == world.identity.url)
        #expect(first.category == "软件本体")
        #expect(first.confidence == .certain)
        #expect(result.items.count == 1)
        #expect(result.unreadableLocations.isEmpty)
    }

    @Test func findsLeftoversAcrossLocationsWithCategories() throws {
        let world = try World()
        try world.temp.makeDirectory("home/Library/Application Support/Tool Pro")
        try world.temp.makeDirectory("home/Library/Caches/org.example.tool")
        try world.temp.makeFile("home/Library/Preferences/org.example.tool.plist")
        try world.temp.makeFile("home/Library/Preferences/ByHost/org.example.tool.ABCD.plist")
        try world.temp.makeDirectory("home/Library/Saved Application State/org.example.tool.savedState")
        try world.temp.makeDirectory("home/Library/Group Containers/TEAM1234.org.example.tool")
        try world.temp.makeFile("home/Library/Logs/DiagnosticReports/Tool Pro_2026-09-21-1015.crash")
        try world.temp.makeFile("home/Library/LaunchAgents/org.example.tool.agent.plist")
        try world.temp.makeDirectory("var/C/org.example.tool")
        try world.temp.makeFile("root/Library/LaunchDaemons/org.example.tool.daemon.plist")
        try world.temp.makeFile("root/private/var/db/receipts/org.example.tool.pkg.bom")
        // 无关的东西
        try world.temp.makeDirectory("home/Library/Application Support/Other App")
        try world.temp.makeFile("home/Library/Preferences/com.apple.finder.plist")

        let result = world.scanner.scan(identity: world.identity)

        #expect(names(result, .certain) == [
            "Tool Pro", "org.example.tool", "org.example.tool.plist", "org.example.tool.ABCD.plist",
            "org.example.tool.savedState", "TEAM1234.org.example.tool", "Tool Pro_2026-09-21-1015.crash",
            "org.example.tool.agent.plist", "org.example.tool.daemon.plist", "org.example.tool.pkg.bom",
        ])
        #expect(names(result, .possible).isEmpty)

        let byName = Dictionary(result.items.map { ($0.url.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(byName["org.example.tool.plist"]?.category == "偏好设置")
        #expect(byName["Tool Pro_2026-09-21-1015.crash"]?.category == "崩溃报告")
        #expect(byName["org.example.tool.pkg.bom"]?.category == "安装记录")
        #expect(byName["org.example.tool.agent.plist"]?.isBackgroundService == true)
        #expect(byName["org.example.tool.daemon.plist"]?.isBackgroundService == true)
        #expect(byName["org.example.tool.plist"]?.isBackgroundService == false)
    }

    @Test func hiddenFilesInHomeArePossibleAndOrdinaryHomeFoldersAreIgnored() throws {
        let world = try World()
        try world.temp.makeDirectory("home/.toolpro")
        try world.temp.makeDirectory("home/.config/toolpro")
        try world.temp.makeDirectory("home/.local/share/Tool Pro")
        try world.temp.makeDirectory("home/toolpro")                  // 不是隐藏项：主目录下的普通文件夹不归卸载器管
        try world.temp.makeDirectory("home/.ssh")

        let result = world.scanner.scan(identity: world.identity)

        let possible = result.items.filter { $0.confidence == .possible }.map { $0.url.path.replacingOccurrences(of: world.home.path, with: "~") }
        #expect(Set(possible) == ["~/.toolpro", "~/.config/toolpro", "~/.local/share/Tool Pro"])
        #expect(result.items.allSatisfy { $0.confidence == .possible ? $0.category == "隐藏文件" : true })
    }

    @Test func onlyFirstLevelChildrenAreConsidered() throws {
        let world = try World()
        try world.temp.makeFile("home/Library/Application Support/Other App/org.example.tool/data.bin")

        let result = world.scanner.scan(identity: world.identity)

        #expect(result.items.count == 1)                              // 只有软件本体
    }

    @Test func filesOfAnotherInstalledAppAreSkipped() throws {
        let world = try World()
        try world.temp.makeFile("home/Library/Preferences/org.example.tool.plist")
        try world.temp.makeFile("home/Library/Preferences/org.example.tool.beta.plist")

        let result = world.scanner.scan(identity: world.identity, otherBundleIDs: ["org.example.tool.beta"])

        #expect(names(result, .certain) == ["org.example.tool.plist"])
    }

    @Test func unreadableLocationIsReportedAndScanContinues() throws {
        let world = try World()
        let containers = try world.temp.makeDirectory("home/Library/Containers")
        try world.temp.makeDirectory("home/Library/Containers/org.example.tool")
        try world.temp.makeFile("home/Library/Preferences/org.example.tool.plist")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: containers.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: containers.path) }

        let result = world.scanner.scan(identity: world.identity)

        #expect(result.unreadableLocations.map(\.lastPathComponent) == ["Containers"])
        #expect(names(result, .certain) == ["org.example.tool.plist"])
    }

    @Test func itemsInReadOnlyParentsNeedAdmin() throws {
        let world = try World()
        let daemons = try world.temp.makeDirectory("root/Library/LaunchDaemons")
        try world.temp.makeFile("root/Library/LaunchDaemons/org.example.tool.plist")
        try world.temp.makeFile("home/Library/Preferences/org.example.tool.plist")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: daemons.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: daemons.path) }

        let result = world.scanner.scan(identity: world.identity)

        let daemon = try #require(result.items.first { $0.url.path.contains("LaunchDaemons") })
        let preference = try #require(result.items.first { $0.url.path.contains("/home/Library/Preferences/") })
        #expect(daemon.needsAdmin)
        #expect(!preference.needsAdmin)
    }

    @Test func readOnlyDirectoryItselfNeedsAdminEvenInAWritableParent() throws {
        // App Store 装的软件：/Applications 可写，但 .app 目录属于 root，普通用户搬不动
        let world = try World()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: world.appURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: world.appURL.path) }

        let result = world.scanner.scan(identity: world.identity)

        #expect(result.items.first?.needsAdmin == true)
    }

    @Test func cancellationStopsEarly() throws {
        let world = try World()
        try world.temp.makeFile("home/Library/Preferences/org.example.tool.plist")

        let result = world.scanner.scan(identity: world.identity, isCancelled: { true })

        #expect(result.items.count == 1)                              // 只来得及放进软件本体
    }

    @Test func scanNeverModifiesAnything() throws {
        let world = try World()
        let file = try world.temp.makeFile("home/Library/Preferences/org.example.tool.plist")
        let folder = try world.temp.makeDirectory("home/Library/Caches/org.example.tool")

        _ = world.scanner.scan(identity: world.identity)

        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: world.appURL.path))
    }
}
