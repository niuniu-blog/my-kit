import Foundation
import Testing
@testable import UninstallerModule

@Suite struct AppIdentityTests {
    @Test func readsIdentityFromInfoPlist() throws {
        let temp = try TempDir()
        let appURL = try temp.makeApp("Applications/WeChat.app", bundleID: "com.tencent.xinWeChat",
                                      name: "WeChat", displayName: "微信", version: "3.8.2")

        let identity = try #require(AppIdentity(appURL: appURL))

        #expect(identity.url == appURL.standardizedFileURL)
        #expect(identity.bundleID == "com.tencent.xinWeChat")
        #expect(identity.displayName == "微信")
        #expect(identity.version == "3.8.2")
        #expect(identity.nameVariants == ["wechat"])          // "微信" 只有 2 个字符，被丢弃
        #expect(identity.vendorFragment == "tencent")
        #expect(identity.lastIDSegment == "xinwechat")
    }

    @Test func fallsBackToBundleNameThenFileName() throws {
        let temp = try TempDir()
        let withName = try temp.makeApp("A/Some Tool.app", bundleID: "org.example.sometool", name: "SomeTool")
        let bare = try temp.makeApp("A/Plain Tool.app", bundleID: nil)

        #expect(AppIdentity(appURL: withName)?.displayName == "SomeTool")
        #expect(AppIdentity(appURL: bare)?.displayName == "Plain Tool")
        #expect(AppIdentity(appURL: bare)?.bundleID == nil)
    }

    @Test func nameVariantsIncludeSpacelessFormsLowercasedAndDeduplicated() {
        let identity = AppIdentity(
            url: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
            bundleID: "com.microsoft.VSCode", names: ["Visual Studio Code", "Code"])

        #expect(identity.nameVariants == ["visual studio code", "visualstudiocode", "code"])
    }

    @Test func shortNamesAreDropped() {
        let identity = AppIdentity(url: URL(fileURLWithPath: "/Applications/QQ.app"), bundleID: "com.tencent.qq", names: ["QQ"])
        #expect(identity.nameVariants.isEmpty)
        #expect(identity.lastIDSegment == nil)                // "qq" 太短
    }

    @Test func genericVendorsAndSegmentsAreNotUsed() {
        let chrome = AppIdentity(url: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
                                 bundleID: "com.google.Chrome", names: ["Google Chrome"])
        #expect(chrome.vendorFragment == nil)                 // google 在通用词名单里
        #expect(chrome.lastIDSegment == "chrome")

        let helper = AppIdentity(url: URL(fileURLWithPath: "/Applications/X.app"), bundleID: "io.acme.desktop", names: ["Acme"])
        #expect(helper.vendorFragment == "acme")
        #expect(helper.lastIDSegment == nil)                  // desktop 太通用

        let twoSegments = AppIdentity(url: URL(fileURLWithPath: "/Applications/Y.app"), bundleID: "maccy.app", names: ["Maccy"])
        #expect(twoSegments.vendorFragment == nil)            // 只有两段，没有"厂商"
    }

    @Test func blankBundleIDCountsAsMissing() {
        let identity = AppIdentity(url: URL(fileURLWithPath: "/Applications/Z.app"), bundleID: "  ", names: ["Zeta"])
        #expect(identity.bundleID == nil)
    }

    @Test func rejectsThingsThatAreNotAppBundles() throws {
        let temp = try TempDir()
        let folder = try temp.makeDirectory("NotAnApp")
        let file = try temp.makeFile("Fake.app")               // 是文件，不是目录
        let noPlist = try temp.makeDirectory("Empty.app")

        #expect(AppIdentity(appURL: folder) == nil)
        #expect(AppIdentity(appURL: file) == nil)
        #expect(AppIdentity(appURL: noPlist) == nil)
    }
}
