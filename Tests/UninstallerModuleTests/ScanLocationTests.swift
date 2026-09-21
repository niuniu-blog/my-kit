import Foundation
import Testing
@testable import UninstallerModule

@Suite struct ScanLocationTests {
    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    private let root = URL(fileURLWithPath: "/", isDirectory: true)

    private func locations() -> [ScanLocation] {
        ScanLocation.all(
            home: home, systemRoot: root,
            userCacheDirectory: URL(fileURLWithPath: "/var/folders/ab/cd/C", isDirectory: true),
            userTempDirectory: URL(fileURLWithPath: "/var/folders/ab/cd/T", isDirectory: true))
    }

    private func location(_ path: String) -> ScanLocation? {
        locations().first { $0.url.path == path }
    }

    @Test func coversEveryLocationInTheSpec() {
        let paths = Set(locations().map(\.url.path))
        let expected = [
            "/Users/tester/Library/Application Support", "/Users/tester/Library/Caches",
            "/Users/tester/Library/Preferences", "/Users/tester/Library/Preferences/ByHost",
            "/Users/tester/Library/Logs", "/Users/tester/Library/Logs/DiagnosticReports",
            "/Users/tester/Library/Saved Application State", "/Users/tester/Library/Containers",
            "/Users/tester/Library/Group Containers", "/Users/tester/Library/Application Scripts",
            "/Users/tester/Library/HTTPStorages", "/Users/tester/Library/Cookies", "/Users/tester/Library/WebKit",
            "/Users/tester/Library/LaunchAgents", "/Users/tester/Library/Autosave Information",
            "/Users/tester/Library/Services", "/Users/tester/Library/PreferencePanes",
            "/Users/tester/Library/Internet Plug-Ins",
            "/var/folders/ab/cd/C", "/var/folders/ab/cd/T",
            "/Users/tester", "/Users/tester/.config", "/Users/tester/.cache", "/Users/tester/.local/share",
            "/Library/Application Support", "/Library/Caches", "/Library/Logs", "/Library/Preferences",
            "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools",
            "/private/var/db/receipts",
        ]
        for path in expected {
            #expect(paths.contains(path), "\(path)")
        }
        #expect(paths.count == expected.count)
    }

    @Test func kindsCategoriesAndFlags() throws {
        #expect(location("/Users/tester/Library/Application Support")?.kind == .byName)
        #expect(location("/Users/tester/Library/Preferences")?.kind == .byIdentifier)
        #expect(location("/Users/tester/Library/Logs/DiagnosticReports")?.kind == .crashReports)
        #expect(location("/Users/tester")?.kind == .hidden)
        #expect(location("/Users/tester/.config")?.category == "隐藏文件")
        #expect(location("/Users/tester/Library/Caches")?.category == "缓存")

        let userAgents = try #require(location("/Users/tester/Library/LaunchAgents"))
        #expect(userAgents.isBackgroundService)
        #expect(!userAgents.isSystemLevel)

        let daemons = try #require(location("/Library/LaunchDaemons"))
        #expect(daemons.isBackgroundService)
        #expect(daemons.isSystemLevel)
        #expect(daemons.category == "后台服务")

        let receipts = try #require(location("/private/var/db/receipts"))
        #expect(receipts.isSystemLevel)
        #expect(!receipts.isBackgroundService)
        #expect(receipts.category == "安装记录")
    }

    @Test func missingPerUserDirectoriesAreSimplyLeftOut() {
        let without = ScanLocation.all(home: home, systemRoot: root, userCacheDirectory: nil, userTempDirectory: nil)
        #expect(!without.contains { $0.category == "系统临时缓存" })
    }

    @Test func systemRootIsInjectable() {
        let fake = URL(fileURLWithPath: "/tmp/fake-root", isDirectory: true)
        let all = ScanLocation.all(home: home, systemRoot: fake, userCacheDirectory: nil, userTempDirectory: nil)
        #expect(all.contains { $0.url.path == "/tmp/fake-root/Library/LaunchDaemons" })
        #expect(!all.contains { $0.url.path == "/Library/LaunchDaemons" })
    }

    @Test func perUserCacheDirectoryComesFromTheSystem() throws {
        let cache = try #require(ScanLocation.darwinUserDirectory(_CS_DARWIN_USER_CACHE_DIR))
        #expect(cache.path.contains("/var/folders/"))
    }
}
