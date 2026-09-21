import Foundation
import Testing
@testable import UninstallerModule

@Suite struct LeftoverMatcherTests {
    private let wechat = AppIdentity(
        url: URL(fileURLWithPath: "/Applications/WeChat.app"),
        bundleID: "com.tencent.xinWeChat", names: ["微信", "WeChat"])
    private let vscode = AppIdentity(
        url: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
        bundleID: "com.microsoft.VSCode", names: ["Visual Studio Code", "Code"])
    private let chrome = AppIdentity(
        url: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
        bundleID: "com.google.Chrome", names: ["Google Chrome"])
    private let docker = AppIdentity(
        url: URL(fileURLWithPath: "/Applications/Docker.app"),
        bundleID: "com.docker.docker", names: ["Docker"])
    private let noID = AppIdentity(
        url: URL(fileURLWithPath: "/Applications/Old Tool.app"), bundleID: nil, names: ["Old Tool"])

    private struct Case {
        let name: String
        let kind: ScanLocation.Kind
        let expected: Confidence?
        init(_ name: String, _ kind: ScanLocation.Kind, _ expected: Confidence?) {
            self.name = name
            self.kind = kind
            self.expected = expected
        }
    }

    private func check(_ cases: [Case], _ identity: AppIdentity, others: Set<String> = []) {
        for item in cases {
            let actual = LeftoverMatcher.match(fileName: item.name, kind: item.kind, identity: identity, otherBundleIDs: others)
            #expect(actual == item.expected, "\(item.name) in \(item.kind)")
        }
    }

    @Test func bundleIdentifierNamesAreCertainEverywhere() {
        check([
            Case("com.tencent.xinWeChat", .byIdentifier, .certain),                       // Containers
            Case("com.tencent.xinWeChat.plist", .byIdentifier, .certain),                 // Preferences
            Case("COM.TENCENT.XINWECHAT.plist", .byIdentifier, .certain),                 // 不区分大小写
            Case("com.tencent.xinWeChat.savedState", .byName, .certain),                  // Saved Application State
            Case("com.tencent.xinWeChat.binarycookies", .byIdentifier, .certain),         // Cookies
            Case("com.tencent.xinWeChat.helper", .byIdentifier, .certain),                // 自带的辅助程序
            Case("com.tencent.xinWeChat.plist.lockfile", .byIdentifier, .certain),
            Case("5A4RE8SF68.com.tencent.xinWeChat", .byIdentifier, .certain),            // Group Containers：TEAMID 前缀
            Case("group.com.tencent.xinWeChat.shared", .byIdentifier, .certain),
            Case("com.tencent.xinWeChat.8A1B2C3D-0000-1111-2222-333344445555.plist", .byIdentifier, .certain),  // ByHost
            Case("com.tencent.xinWeChat.bom", .byIdentifier, .certain),                   // 安装记录
            Case("com.tencent.xinWeChat", .byName, .certain),                             // 缓存目录也常用 id 命名
            Case("com.tencent.xinWeChat", .hidden, .certain),
        ], wechat)
    }

    @Test func similarButDifferentIdentifiersAreNotCertain() {
        check([
            Case("com.tencent.xinWeChatWork.plist", .byIdentifier, nil),                  // 企业微信：id 只是前缀相同
            Case("com.tencent.qq.plist", .byIdentifier, nil),
            Case("com.tencent.plist", .byIdentifier, nil),
            Case("xcom.tencent.xinWeChat", .byIdentifier, .possible),                     // 前面紧挨着字母：不算 id 命中，只是含有末段
        ], wechat)
    }

    @Test func exactAppNameIsCertainOnlyInNameBasedLocations() {
        check([
            Case("Docker", .byName, .certain),
            Case("docker", .byName, .certain),
            Case("Docker.log", .byName, .certain),                                        // 去掉 .log 后完全相同
            Case("Docker", .byIdentifier, .possible),                                     // 偏好设置目录里的同名项：只算可能
            Case("Docker Desktop", .byName, .possible),
        ], docker)
        check([
            Case("Code", .byName, .certain),
            Case("Visual Studio Code", .byName, .certain),
            Case("VisualStudioCode", .byName, .certain),
        ], vscode)
    }

    @Test func crashReportsMatchByNamePrefix() {
        check([
            Case("Docker_2026-09-21-101500_MacBook.crash", .crashReports, .certain),
            Case("Docker-2026-09-21-101500.ips", .crashReports, .certain),
            Case("Docker_2026-09-21-101500_MacBook.diag", .crashReports, .certain),
            Case("DockerHelper_2026-09-21.crash", .crashReports, nil),
            Case("Docker_2026-09-21.crash", .byName, .possible),                          // 不在崩溃报告目录：只算可能
        ], docker)
    }

    @Test func hiddenFilesNamedAfterTheAppArePossible() {
        check([
            Case(".docker", .hidden, .possible),
            Case("docker", .hidden, .possible),                                           // ~/.config/docker
            Case(".dockerignore-global", .hidden, nil),
            Case(".npm", .hidden, nil),
        ], docker)
        // .vscode 含 bundle id 的末段 "vscode"；.code 去掉点之后等于名称变体 "code"
        check([Case(".vscode", .hidden, .possible), Case(".code", .hidden, .possible)], vscode)
    }

    @Test func vendorFolderIsOnlyPossible() {
        check([
            Case("Tencent", .byName, .possible),
            Case("tencent", .hidden, .possible),
            Case("TencentMeeting", .byName, nil),
        ], wechat)
        check([Case("Google", .byName, nil), Case("Microsoft", .byName, nil)], chrome)     // 通用厂商名不参与
    }

    @Test func containmentNeedsWordBoundaries() {
        check([
            Case("Xcode", .byName, nil),                                                  // 卸载 Code 不能牵连 Xcode
            Case("com.example.xcode-tools", .byIdentifier, nil),
            Case("Code Helper", .byName, .possible),
            Case("code-insiders", .hidden, .possible),
            Case("com.github.vscode-extras", .byIdentifier, .possible),                   // 含 id 末段 vscode
            Case("barcode", .byName, nil),
        ], vscode)
    }

    @Test func shortAndGenericNamesNeverMatchByName() {
        let qq = AppIdentity(url: URL(fileURLWithPath: "/Applications/QQ.app"), bundleID: "com.tencent.qq", names: ["QQ"])
        check([
            Case("QQ", .byName, nil),
            Case("qqmusic", .byName, nil),
            Case("com.tencent.qq.plist", .byIdentifier, .certain),
            Case("com.tencent.qqmusic.plist", .byIdentifier, nil),
        ], qq)
    }

    @Test func appleDataIsNeverTouched() {
        check([
            Case("com.apple.Safari.plist", .byIdentifier, nil),
            Case("com.apple.docker.plist", .byIdentifier, nil),
        ], docker)
    }

    @Test func filesOfAMoreSpecificInstalledAppAreLeftAlone() {
        let others: Set<String> = ["com.google.Chrome.canary", "com.google.Chrome", "com.tencent.qq"]
        check([
            Case("com.google.Chrome.plist", .byIdentifier, .certain),
            Case("com.google.Chrome.canary.plist", .byIdentifier, nil),                   // 属于 Chrome Canary
            Case("com.google.Chrome.canary", .byName, nil),
            Case("com.google.Chrome.helper.plist", .byIdentifier, .certain),
        ], chrome, others: others)

        let canary = AppIdentity(url: URL(fileURLWithPath: "/Applications/Google Chrome Canary.app"),
                                 bundleID: "com.google.Chrome.canary", names: ["Google Chrome Canary"])
        check([
            Case("com.google.Chrome.canary.plist", .byIdentifier, .certain),
            Case("com.google.Chrome.plist", .byIdentifier, nil),                          // 属于正式版 Chrome
        ], canary, others: others)
    }

    @Test func appsWithoutBundleIdentifierMatchByNameOnly() {
        check([
            Case("Old Tool", .byName, .certain),
            Case("OldTool", .byName, .certain),
            Case("old tool.plist", .byIdentifier, .possible),
            Case("com.example.oldtool.plist", .byIdentifier, .possible),
            Case("Unrelated", .byName, nil),
        ], noID)
    }

    @Test func emptyAndSuffixOnlyNamesAreIgnored() {
        check([Case("", .byName, nil), Case(".plist", .byIdentifier, nil), Case(".log", .byName, nil)], docker)
    }

    @Test func wordBoundaryHelper() {
        #expect(LeftoverMatcher.containsWord("code helper", "code"))
        #expect(LeftoverMatcher.containsWord("my-code", "code"))
        #expect(LeftoverMatcher.containsWord("code", "code"))
        #expect(!LeftoverMatcher.containsWord("xcode", "code"))
        #expect(!LeftoverMatcher.containsWord("codes", "code"))
        #expect(LeftoverMatcher.containsWord("xcode code", "code"))                        // 第一处不算，第二处算
        #expect(!LeftoverMatcher.containsWord("anything", ""))
    }
}
