import Foundation
import Testing
@testable import UninstallerModule

@Suite struct InstalledAppScannerTests {
    @Test func listsAppsInRootsAndOneSubfolderLevel() throws {
        let temp = try TempDir()
        try temp.makeApp("Applications/Alpha.app", bundleID: "org.example.alpha", name: "Alpha")
        try temp.makeApp("Applications/Suite/Beta.app", bundleID: "org.example.beta", name: "Beta")
        try temp.makeApp("Applications/Suite/Deep/Gamma.app", bundleID: "org.example.gamma")       // 太深，不列
        try temp.makeApp("home/Applications/Delta.app", bundleID: "org.example.delta", name: "Delta")
        try temp.makeDirectory("Applications/NotAnApp")
        try temp.makeFile("Applications/readme.txt")

        let scanner = InstalledAppScanner(roots: [
            temp.url.appendingPathComponent("Applications"),
            temp.url.appendingPathComponent("home/Applications"),
            temp.url.appendingPathComponent("Missing"),
        ])
        let list = scanner.scan()

        #expect(list.apps.map(\.identity.displayName).sorted() == ["Alpha", "Beta", "Delta"])
        #expect(list.allBundleIDs == ["org.example.alpha", "org.example.beta", "org.example.delta"])
    }

    @Test func doesNotLookInsideAppBundles() throws {
        let temp = try TempDir()
        try temp.makeApp("Applications/Host.app", bundleID: "org.example.host", name: "Host")
        try temp.makeApp("Applications/Host.app/Contents/Helpers/Helper.app", bundleID: "org.example.host.helper")

        let list = InstalledAppScanner(roots: [temp.url.appendingPathComponent("Applications")]).scan()

        #expect(list.apps.map(\.identity.displayName) == ["Host"])
    }

    @Test func protectedAppsAreHiddenButTheirIdentifiersAreStillCollected() throws {
        let temp = try TempDir()
        try temp.makeApp("Applications/Safari.app", bundleID: "com.apple.Safari", name: "Safari")
        try temp.makeApp("Applications/MyKit.app", bundleID: "com.imiros.mykit", name: "MyKit")
        try temp.makeApp("Applications/Tool.app", bundleID: "org.example.tool", name: "Tool")

        let list = InstalledAppScanner(roots: [temp.url.appendingPathComponent("Applications")]).scan()

        #expect(list.apps.map(\.identity.displayName) == ["Tool"])
        #expect(list.allBundleIDs == ["com.apple.Safari", "com.imiros.mykit", "org.example.tool"])
    }

    @Test func symlinkedAppsAndFoldersAreSkipped() throws {
        let temp = try TempDir()
        let real = try temp.makeApp("Elsewhere/Real.app", bundleID: "org.example.real", name: "Real")
        try temp.makeDirectory("Applications")
        try FileManager.default.createSymbolicLink(
            at: temp.url.appendingPathComponent("Applications/Linked.app"), withDestinationURL: real)
        try FileManager.default.createSymbolicLink(
            at: temp.url.appendingPathComponent("Applications/LinkedFolder"), withDestinationURL: temp.url.appendingPathComponent("Elsewhere"))

        let list = InstalledAppScanner(roots: [temp.url.appendingPathComponent("Applications")]).scan()

        #expect(list.apps.isEmpty)
    }

    @Test func sameAppReachedTwiceIsListedOnce() throws {
        let temp = try TempDir()
        try temp.makeApp("Applications/Utilities/Tool.app", bundleID: "org.example.tool", name: "Tool")

        let list = InstalledAppScanner(roots: [
            temp.url.appendingPathComponent("Applications"),
            temp.url.appendingPathComponent("Applications/Utilities"),
        ]).scan()

        #expect(list.apps.count == 1)
    }

    @Test func standardRootsPointAtTheRealApplicationsFolders() {
        let paths = InstalledAppScanner.standard().roots.map(\.path)
        #expect(paths.contains("/Applications"))
        #expect(paths.contains("/Applications/Utilities"))
        #expect(paths.contains { $0.hasSuffix("/Applications") && $0 != "/Applications" })
    }

    @Test func titleDropsTheAppExtension() throws {
        let temp = try TempDir()
        let url = try temp.makeApp("Applications/Nice Tool.app", bundleID: "org.example.nice", name: "NiceTool")
        let app = try #require(InstalledApp(appURL: url))
        #expect(app.title == "Nice Tool")
        #expect(app.sizeBytes == nil)
    }
}
