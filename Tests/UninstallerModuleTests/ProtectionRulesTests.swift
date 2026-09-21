import Foundation
import Testing
@testable import UninstallerModule

@Suite struct ProtectionRulesTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    // MARK: 软件

    @Test func ordinaryAppIsNotProtected() throws {
        let temp = try TempDir()
        let app = try temp.makeApp("Applications/Tool.app", bundleID: "org.example.tool")
        #expect(!ProtectionRules.isProtectedApp(url: app, bundleID: "org.example.tool"))
    }

    @Test func systemAndAppleAppsAreProtected() throws {
        let temp = try TempDir()
        let appleLike = try temp.makeApp("Applications/Safari.app", bundleID: "com.apple.Safari")

        #expect(ProtectionRules.isProtectedApp(url: URL(fileURLWithPath: "/System/Applications/Mail.app"), bundleID: "com.apple.mail"))
        #expect(ProtectionRules.isProtectedApp(url: appleLike, bundleID: "com.apple.Safari"))
        #expect(ProtectionRules.isProtectedApp(url: appleLike, bundleID: "COM.APPLE.Safari"))
    }

    @Test func myKitItselfIsProtected() throws {
        let temp = try TempDir()
        let own = try temp.makeApp("Applications/MyKit.app", bundleID: "com.imiros.mykit")
        #expect(ProtectionRules.isProtectedApp(url: own, bundleID: "com.imiros.mykit"))
    }

    @Test func nonAppsMissingPathsAndSymlinksAreProtected() throws {
        let temp = try TempDir()
        let folder = try temp.makeDirectory("Applications/Folder")
        let real = try temp.makeApp("Applications/Real.app", bundleID: "org.example.real")
        let link = temp.url.appendingPathComponent("Applications/Link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        #expect(ProtectionRules.isProtectedApp(url: folder, bundleID: "org.example.folder"))
        #expect(ProtectionRules.isProtectedApp(url: temp.url.appendingPathComponent("Missing.app"), bundleID: "org.example.missing"))
        #expect(ProtectionRules.isProtectedApp(url: link, bundleID: "org.example.real"))
    }

    // MARK: 路径

    @Test func normalizedPathRemovesPrivatePrefixAndDotDot() {
        #expect(ProtectionRules.normalizedPath(URL(fileURLWithPath: "/private/var/db/receipts")) == "/var/db/receipts")
        #expect(ProtectionRules.normalizedPath(URL(fileURLWithPath: "/private/var/folders/ab/cd/C/x")) == "/var/folders/ab/cd/C/x")
        #expect(ProtectionRules.normalizedPath(URL(fileURLWithPath: "/var/folders/ab/cd/C/x")) == "/var/folders/ab/cd/C/x")
        #expect(ProtectionRules.normalizedPath(URL(fileURLWithPath: "/Users/tester/Library/Caches/../Logs")) == "/Users/tester/Library/Logs")
        #expect(ProtectionRules.normalizedPath(URL(fileURLWithPath: "/privateer/file")) == "/privateer/file")
    }

    @Test func systemAndStructuralPathsAreForbidden() {
        let forbidden = [
            "/", "/Applications", "/Library", "/System", "/System/Library/CoreServices", "/usr", "/usr/local/bin",
            "/bin/ls", "/sbin", "/private/var/db", "/var/db", "/private/var/db/receipts", "/private/var/folders", "/tmp",
            "/Users", "/Users/tester", "/Users/tester/Library",
        ]
        for path in forbidden {
            #expect(ProtectionRules.isForbiddenPath(URL(fileURLWithPath: path), home: home), "\(path)")
        }
    }

    @Test func sensitiveHomeItemsAreForbidden() {
        for name in [".ssh", ".Trash", ".zshrc", ".gitconfig", ".config", ".local"] {
            #expect(ProtectionRules.isForbiddenPath(home.appendingPathComponent(name), home: home), "\(name)")
        }
        #expect(!ProtectionRules.isForbiddenPath(home.appendingPathComponent(".docker"), home: home))
    }

    @Test func scanRootsThemselvesAreForbiddenButTheirChildrenAreNot() {
        let root = home.appendingPathComponent("Library/Preferences")
        #expect(ProtectionRules.isForbiddenPath(root, home: home, scanRoots: [root]))
        #expect(!ProtectionRules.isForbiddenPath(root.appendingPathComponent("org.example.tool.plist"), home: home, scanRoots: [root]))
    }

    @Test func pathsWithControlCharactersAreForbidden() {
        let weird = home.appendingPathComponent("Library/Caches/bad\nname")
        #expect(ProtectionRules.isForbiddenPath(weird, home: home))
    }

    // MARK: 执行前复核

    @Test func removalIsAllowedOnlyForTheAppOrDirectChildrenOfScanRoots() throws {
        let temp = try TempDir()
        let fakeHome = try temp.makeDirectory("home")
        let caches = try temp.makeDirectory("home/Library/Caches")
        let app = try temp.makeApp("Applications/Tool.app", bundleID: "org.example.tool")
        let child = try temp.makeDirectory("home/Library/Caches/org.example.tool")
        let nested = try temp.makeFile("home/Library/Caches/org.example.tool/deep/file.bin")
        let elsewhere = try temp.makeFile("home/Documents/report.txt")

        func check(_ url: URL) -> ProtectionRules.RemovalCheck {
            ProtectionRules.checkRemoval(of: url, appURL: app, appBundleID: "org.example.tool", scanRoots: [caches], home: fakeHome)
        }

        #expect(check(app) == .allowed)
        #expect(check(child) == .allowed)
        #expect(check(nested) == .rejected("路径不在允许范围内"))
        #expect(check(elsewhere) == .rejected("路径不在允许范围内"))
        #expect(check(caches) == .rejected("路径不在允许范围内"))
        #expect(check(fakeHome) == .rejected("路径不在允许范围内"))
    }

    @Test func dotDotTricksAreResolvedBeforeChecking() throws {
        let temp = try TempDir()
        let fakeHome = try temp.makeDirectory("home")
        let caches = try temp.makeDirectory("home/Library/Caches")
        let app = try temp.makeApp("Applications/Tool.app", bundleID: "org.example.tool")
        try temp.makeFile("home/Documents/secret.txt")
        let sneaky = caches.appendingPathComponent("../../Documents/secret.txt")

        let result = ProtectionRules.checkRemoval(of: sneaky, appURL: app, appBundleID: "org.example.tool", scanRoots: [caches], home: fakeHome)

        #expect(result == .rejected("路径不在允许范围内"))
    }

    @Test func protectedAppIsRejectedEvenIfItIsTheTarget() throws {
        let temp = try TempDir()
        let fakeHome = try temp.makeDirectory("home")
        let apple = try temp.makeApp("Applications/Notes.app", bundleID: "com.apple.Notes")

        let result = ProtectionRules.checkRemoval(of: apple, appURL: apple, appBundleID: "com.apple.Notes", scanRoots: [], home: fakeHome)

        #expect(result == .rejected("这是系统软件，不能卸载"))
    }
}
