# MyKit 卸载器模块 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 MyKit 增加"卸载软件"：在窗口里选一个已安装的软件（或把 `.app` 拖进来），找出它的本体和散落各处的残留文件（含隐藏文件、系统级目录、安装记录），让用户过目、勾选、确认后**移到废纸篓**。

**Architecture:** 新增 Target `UninstallerModule`（依赖 `Core`）。纯规则（软件身份、保护规则、名字匹配、搜索排序、路径显示）与只读的文件系统扫描（位置表、残留扫描、已安装软件、大小计算）分离；唯一会改动文件的地方是 `Trasher`，它只有两条执行路径 —— `FileManager.trashItem` 与"请访达移到废纸篓" —— 都通过协议注入，测试里全部是假实现；每一条在执行前都要再过一遍 `ProtectionRules.checkRemoval`。`UninstallerViewModel` 把以上组合成窗口的状态机，所有会碰系统的操作经 `UninstallerDependencies` 注入。窗口只在打开时存在，关闭即释放全部数据。

**Tech Stack:** Swift 6.4（语言模式 5）、AppKit、SwiftUI、UniformTypeIdentifiers、Foundation（`PropertyListSerialization`、`FileManager`、`NSAppleScript`）、Darwin `confstr`、Swift Testing。无第三方依赖。

**Spec:** `docs/superpowers/specs/2026-09-21-mykit-uninstaller-design.md`

## Global Constraints

- 运行环境：macOS 27，只有 Command Line Tools，**没有 Xcode**。不要使用 `xcodebuild`、`.xcodeproj`、XCTest。
- 构建必须带 `--build-system native`（会有一条 deprecated 警告，忽略）。跑测试**只用** `scripts/test.sh`；直接 `swift test` 会报 `no such module 'Testing'`。
- 测试框架：Swift Testing（`import Testing`、`@Test`、`#expect`、`#require`）。
- **`#expect` 里不要写字面量算术**（如 `x == 1600 - 16` 会因类型推断失败而误报），先用 `let` 算好或直接写结果；`try` / `await` 的值同理先取出来再比较。
- **不要写 `@State`**（macOS 27 SDK 里是宏，CLT 下没有宏插件）；需要时用 `Core` 里的别名 `@ViewState`。同理不要用 `#Preview`、`@Entry`、`@Animatable`。本计划的界面状态全部放在 `UninstallerViewModel`（`ObservableObject`）里，只用 `@ObservedObject` 和 `@Binding`。
- 最低系统 macOS 14；更高版本的 API 必须包在 `#available` 里（本计划没有用到）。
- 不引入任何第三方依赖；**不调用任何外部命令**（不写 `Process`、`NSTask`、`system()`、`popen()`，不调用 `osascript` / `rm`）；不联网。Swift 语言模式 5；目标是零编译警告。
- 所有界面相关的类型标 `@MainActor`。扫描和大小计算必须放到后台任务里（`Task.detached`），用取消标记支持取消，结果回到主线程再用。
- 不得有任何常驻的东西：没有定时器、没有文件监视、没有后台线程；窗口关闭后模块不保留任何数据。
- 所有面向用户的文案用简体中文。
- 终端是 zsh：查日志用 `/usr/bin/log`（`log` 是 zsh 内建命令），只看 App 自己的日志要加 `process == "MyKit"` 过滤（测试进程会以同一个日志分类写日志）；zsh 数组下标从 1 开始。
- 每个任务结束时 `scripts/test.sh` 必须全绿、零警告，然后提交。
- 本计划修改已有文件时一律给出**完整的新文件内容**（整体替换）。动手前先确认工作区干净（`git status`），文件内容与计划写作时一致。

### 安全红线（这个模块会移动用户的文件，以下每一条都是硬性要求）

- **模块的正式代码里不允许出现任何永久删除**：不写 `removeItem`、`unlink`、`rmdir`、`recycle(`，不让访达"清空废纸篓"，不写 `forceTerminate`。移走文件只有两种写法，且只允许出现在 `Sources/UninstallerModule/SystemTrashers.swift` 里：`FileManager.trashItem` 和发给访达的 `delete`（访达的 `delete` = 移到废纸篓）。Task 4 里的 `NoPermanentDeleteTests` 会扫描源码强制这一点 —— 连注释和局部函数名都不要用这些词。
- **任何测试都不得移动、删除或改动真实文件**：文件系统测试只在 `TempDir`（测试辅助类，位于系统临时目录下的随机子目录）里进行；`Trasher` 和视图模型的测试一律注入假执行器。测试代码里不得调用 `FileManager.trashItem`、`NSWorkspace.recycle`、`NSAppleScript`、`osascript`，不得读写 `~/Library`、`/Applications`、`/Library`、废纸篓。（`TempDir` 在 `deinit` 里清掉自己的临时目录，这是测试代码，不受第一条限制。）
- 实现过程中**不要**为了"试一下"而真的卸载任何东西；不要在终端里运行 `osascript`；不要读取 `~/Library/Containers`、`~/Library/Group Containers`、`~/Library/Cookies` 等受系统保护的目录（会在用户屏幕上弹出授权提示）。真机上的卸载验证只在 Task 6 的手动验收里、由用户本人按清单操作。
- 每一条要移走的路径在执行前必须经过 `ProtectionRules.checkRemoval`；不要绕过它，也不要放宽它。

## File Structure

```
Package.swift                                    修改  Task 1 新增 UninstallerModule 及其测试 Target；Task 6 让 MyKit 依赖它
Resources/Info.plist                             修改  Task 6 增加 NSAppleEventsUsageDescription
README.md                                        修改  Task 6 增加"卸载软件怎么用"

Sources/UninstallerModule/
  AppIdentity.swift                              新增  从 Info.plist 读出 bundle id / 名称 / 版本；名称变体、厂商片段
  ProtectionRules.swift                          新增  不可卸载的软件、不可移动的路径、执行前复核、路径规范化
  ScanLocation.swift                             新增  设计文档 §3.2 的位置表（主目录 / 系统根目录可注入）
  LeftoverMatcher.swift                          新增  Confidence；只看名字的匹配规则（纯函数）
  LeftoverScanner.swift                          新增  LeftoverItem / LeftoverScanResult；只读扫描各位置的一级子项
  InstalledAppScanner.swift                      新增  InstalledApp / InstalledAppList；列出已安装软件
  SizeCalculator.swift                           新增  已分配大小（可取消）与格式化
  AppListing.swift                               新增  搜索与排序
  Trasher.swift                                  新增  FileTrashing / PrivilegedTrashing 协议、TrashReport、执行流程
  SystemTrashers.swift                           新增  两个正式执行器：DirectTrasher、FinderTrasher
  UninstallerDependencies.swift                  新增  依赖注入、RunningAppControl、CancellationFlag、PathDisplay
  UninstallerViewModel.swift                     新增  窗口的全部状态与状态机
  UninstallerViews.swift                         新增  SwiftUI 界面、PrivacyPane、AppIconStore
  UninstallerWindowController.swift              新增  窗口的创建与释放
  UninstallerModule.swift                        新增  AppModule 实现

Sources/MyKit/AppDelegate.swift                  修改  Task 6 注册卸载器（排在截图之后）

Tests/UninstallerModuleTests/
  TestSupport.swift                              新增  TempDir：临时目录、伪造 .app
  AppIdentityTests.swift / ProtectionRulesTests.swift                          Task 1
  LeftoverMatcherTests.swift / ScanLocationTests.swift / LeftoverScannerTests.swift   Task 2
  InstalledAppScannerTests.swift / SizeAndListingTests.swift                   Task 3
  TrasherTests.swift（含 NoPermanentDeleteTests）                               Task 4
  UninstallerViewModelTests.swift（含 PathDisplayTests）                        Task 5
  UninstallerModuleTests.swift                                                 Task 6
```

任务顺序：1 身份与保护规则 → 2 位置表、匹配、残留扫描 → 3 已安装软件、大小、搜索排序 → 4 移到废纸篓（只用假执行器测试）→ 5 视图模型 → 6 界面、总装、使用说明、验收。

---

### Task 1: Target、软件身份、保护规则

**Files:**
- Modify: `Package.swift`
- Create: `Sources/UninstallerModule/AppIdentity.swift`, `Sources/UninstallerModule/ProtectionRules.swift`
- Test: `Tests/UninstallerModuleTests/TestSupport.swift`, `Tests/UninstallerModuleTests/AppIdentityTests.swift`, `Tests/UninstallerModuleTests/ProtectionRulesTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `public struct AppIdentity: Equatable, Sendable { url: URL; bundleID: String?; displayName: String; version: String?; nameVariants: [String]; vendorFragment: String?; lastIDSegment: String? }`；`init(url:bundleID:names:version:)`（纯构造，测试和拖放用）；`init?(appURL:)`（读磁盘上的 `.app`）
  - `public enum ProtectionRules`：`ownBundleID`；`isProtectedApp(url:bundleID:) -> Bool`；`normalizedPath(_:) -> String`；`isForbiddenPath(_:home:scanRoots:) -> Bool`；`enum RemovalCheck { case allowed, rejected(String) }`；`checkRemoval(of:appURL:appBundleID:scanRoots:home:) -> RemovalCheck`
  - 测试辅助 `TempDir`：`url`、`makeDirectory(_:)`、`makeFile(_:bytes:)`、`makeApp(_:bundleID:name:displayName:version:payloadBytes:)`

要点：系统对 `/private/var/…` 的标准化不一致（已存在的路径会被去掉 `/private`，不存在的不会），所以一切路径比较都先过 `normalizedPath`。

- [ ] **Step 1: 更新 `Package.swift`**

完整内容（本任务只加库和测试 Target；`MyKit` 在 Task 6 才依赖它）：

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyKit",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Core"),
        .target(
            name: "ClipboardModule",
            dependencies: ["Core"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "ScreenshotModule", dependencies: ["Core"]),
        .target(name: "SystemMonitorModule", dependencies: ["Core"]),
        .target(name: "UninstallerModule", dependencies: ["Core"]),
        .executableTarget(
            name: "MyKit",
            dependencies: ["Core", "ClipboardModule", "ScreenshotModule", "SystemMonitorModule"]
        ),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "ClipboardModuleTests", dependencies: ["ClipboardModule"]),
        .testTarget(name: "ScreenshotModuleTests", dependencies: ["ScreenshotModule"]),
        .testTarget(name: "SystemMonitorModuleTests", dependencies: ["SystemMonitorModule"]),
        .testTarget(name: "UninstallerModuleTests", dependencies: ["UninstallerModule"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: 写测试辅助 `Tests/UninstallerModuleTests/TestSupport.swift`**

```swift
import Foundation
@testable import UninstallerModule

/// 测试专用的临时目录。所有文件系统测试都只在这里面进行；对象释放时整个目录被清掉。
/// （清理临时目录是测试代码的事；模块的正式代码里不允许出现任何永久删除。）
final class TempDir {
    let url: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("mykit-uninstaller-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.standardizedFileURL
    }

    deinit {
        // 有的测试会把目录改成只读，清理前先改回来
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let item as URL in enumerator {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: item.path)
            }
        }
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func makeDirectory(_ relativePath: String) throws -> URL {
        let target = url.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    @discardableResult
    func makeFile(_ relativePath: String, bytes: Int = 16) throws -> URL {
        let target = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: target)
        return target
    }

    /// 伪造一个 .app：只有 Contents/Info.plist 和一个假的可执行文件。
    @discardableResult
    func makeApp(
        _ relativePath: String,
        bundleID: String?,
        name: String? = nil,
        displayName: String? = nil,
        version: String? = "1.0",
        payloadBytes: Int = 64
    ) throws -> URL {
        let app = try makeDirectory(relativePath)
        var plist: [String: Any] = [:]
        if let bundleID { plist["CFBundleIdentifier"] = bundleID }
        if let name { plist["CFBundleName"] = name }
        if let displayName { plist["CFBundleDisplayName"] = displayName }
        if let version { plist["CFBundleShortVersionString"] = version }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try makeDirectory(relativePath + "/Contents/MacOS")
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data(repeating: 0x42, count: payloadBytes).write(to: app.appendingPathComponent("Contents/MacOS/fake"))
        return app
    }
}
```

- [ ] **Step 3: 写失败的测试 `Tests/UninstallerModuleTests/AppIdentityTests.swift`**

```swift
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
```

- [ ] **Step 4: 写失败的测试 `Tests/UninstallerModuleTests/ProtectionRulesTests.swift`**

```swift
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
```

- [ ] **Step 5: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 失败 —— `Sources/UninstallerModule` 还没有源文件（SwiftPM 报 target 没有源文件），或 `cannot find 'AppIdentity' in scope`。

- [ ] **Step 6: 写 `Sources/UninstallerModule/AppIdentity.swift`**

```swift
import Foundation

/// 一个待卸载软件的"身份"：用来在各个目录里认出哪些文件是它留下的。
public struct AppIdentity: Equatable, Sendable {
    /// .app 的路径（已标准化，不解析符号链接）
    public let url: URL
    public let bundleID: String?
    /// 显示名：CFBundleDisplayName → CFBundleName → 文件名
    public let displayName: String
    public let version: String?
    /// 用于按名称匹配的变体：全部小写、去重、长度 ≥ 3
    public let nameVariants: [String]
    /// bundle id 的第二段（厂商），小写；太短或太通用时为 nil。只用于"可能相关"
    public let vendorFragment: String?
    /// bundle id 的最后一段，小写；太短或太通用时为 nil。只用于"可能相关"
    public let lastIDSegment: String?

    /// 太通用、不能拿来当匹配依据的词
    static let genericWords: Set<String> = [
        "apple", "google", "microsoft", "github", "app", "mac", "macos", "company",
        "software", "desktop", "client", "helper", "agent", "launcher", "updater", "service",
    ]

    public init(url: URL, bundleID: String?, names: [String], version: String? = nil) {
        self.url = url.standardizedFileURL
        let trimmedID = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleID = (trimmedID?.isEmpty ?? true) ? nil : trimmedID
        let fileName = url.deletingPathExtension().lastPathComponent
        let cleaned = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.displayName = cleaned.first ?? fileName
        self.version = version
        self.nameVariants = Self.variants(from: cleaned + [fileName])

        let segments = (self.bundleID ?? "").lowercased().split(separator: ".").map(String.init)
        if segments.count >= 3, segments[1].count >= 4, !Self.genericWords.contains(segments[1]) {
            self.vendorFragment = segments[1]
        } else {
            self.vendorFragment = nil
        }
        if segments.count >= 2, let last = segments.last, last.count >= 4, !Self.genericWords.contains(last) {
            self.lastIDSegment = last
        } else {
            self.lastIDSegment = nil
        }
    }

    /// 从磁盘上的 .app 读取。不是以 .app 结尾的目录、或读不到 Info.plist 时返回 nil。
    public init?(appURL: URL) {
        var isDirectory: ObjCBool = false
        guard appURL.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: appURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let names = ["CFBundleDisplayName", "CFBundleName"].compactMap { plist[$0] as? String }
        self.init(
            url: appURL,
            bundleID: plist["CFBundleIdentifier"] as? String,
            names: names,
            version: plist["CFBundleShortVersionString"] as? String
        )
    }

    /// 每个名字本身 + 去掉空格的形式；小写、去重、丢掉长度 < 3 的（太短容易误伤）。
    static func variants(from names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in names {
            let lower = name.lowercased()
            for candidate in [lower, lower.replacingOccurrences(of: " ", with: "")] {
                guard candidate.count >= 3, seen.insert(candidate).inserted else { continue }
                result.append(candidate)
            }
        }
        return result
    }
}
```

- [ ] **Step 7: 写 `Sources/UninstallerModule/ProtectionRules.swift`**

```swift
import Foundation

/// 卸载器的安全规则：哪些软件不能卸载、哪些路径永远不能动、执行前的最后一次复核。
public enum ProtectionRules {
    public static let ownBundleID = "com.imiros.mykit"

    /// 主目录下永远不碰的隐藏项（密钥、命令行配置、废纸篓本身等）
    static let sensitiveHomeNames: Set<String> = [
        ".Trash", ".ssh", ".gnupg", ".zshrc", ".zprofile", ".zshenv", ".zsh_history", ".zsh_sessions",
        ".bashrc", ".bash_profile", ".bash_history", ".profile", ".gitconfig", ".netrc",
        ".config", ".cache", ".local", ".DS_Store", ".CFUserTextEncoding",
    ]

    /// 这些目录本身永远不能被移走（它们下面的具体条目另行判断）
    /// 路径一律先经过 normalizedPath（去掉 /private 前缀）再和这张表比较。
    static let forbiddenExactPaths: Set<String> = [
        "/", "/Applications", "/Applications/Utilities", "/Library", "/Users", "/Volumes", "/private",
        "/var", "/var/db", "/var/db/receipts", "/var/folders", "/tmp", "/etc", "/opt", "/cores",
    ]

    /// 这些目录及其下面的一切都不能动
    static let forbiddenPrefixes: [String] = ["/System", "/usr", "/bin", "/sbin"]

    // MARK: 软件

    /// 系统软件、MyKit 自己、不是正常 .app 目录的东西，一律不可卸载。
    public static func isProtectedApp(url: URL, bundleID: String?) -> Bool {
        let standardized = url.standardizedFileURL
        let path = normalizedPath(url)
        if path == "/System" || path.hasPrefix("/System/") { return true }
        if let id = bundleID?.lowercased() {
            if id.hasPrefix("com.apple.") { return true }
            if id == ownBundleID { return true }
        }
        if path == normalizedPath(Bundle.main.bundleURL) { return true }
        guard standardized.pathExtension.lowercased() == "app" else { return true }

        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if values?.isSymbolicLink == true { return true }
        if values?.isDirectory != true { return true }
        return false
    }

    // MARK: 路径

    /// 用于比较的规范路径：解析 `..`（不解析符号链接），并把 /private/var、/private/tmp、/private/etc
    /// 统一成 /var、/tmp、/etc —— 系统对"已存在"和"不存在"的路径处理不一致，这里抹平。
    public static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        for alias in ["/var", "/tmp", "/etc"] where path == "/private" + alias || path.hasPrefix("/private" + alias + "/") {
            path.removeFirst("/private".count)
        }
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    public static func isForbiddenPath(_ url: URL, home: URL, scanRoots: [URL] = []) -> Bool {
        let path = normalizedPath(url)
        if path.isEmpty { return true }
        if path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) { return true }   // 控制字符、换行
        if forbiddenExactPaths.contains(path) { return true }
        for prefix in forbiddenPrefixes where path == prefix || path.hasPrefix(prefix + "/") { return true }

        let homePath = normalizedPath(home)
        if path == homePath || path == homePath + "/Library" { return true }
        if homePath.hasPrefix(path + "/") { return true }                       // 主目录的任何上级
        if normalizedPath(url.deletingLastPathComponent()) == homePath,
           sensitiveHomeNames.contains(url.lastPathComponent) {
            return true
        }
        for root in scanRoots where normalizedPath(root) == path { return true }   // 扫描位置本身
        return false
    }

    public enum RemovalCheck: Equatable {
        case allowed
        case rejected(String)
    }

    /// 执行前对每一条的最后复核：要么是软件本体，要么它的父目录恰好是某个扫描位置。
    public static func checkRemoval(of url: URL, appURL: URL, appBundleID: String?, scanRoots: [URL], home: URL) -> RemovalCheck {
        let target = url.standardizedFileURL
        let name = target.lastPathComponent
        if name.isEmpty || name == "." || name == ".." {
            return .rejected("路径不在允许范围内")
        }
        if isForbiddenPath(target, home: home, scanRoots: scanRoots) {
            return .rejected("路径不在允许范围内")
        }
        if normalizedPath(target) == normalizedPath(appURL) {
            return isProtectedApp(url: appURL, bundleID: appBundleID) ? .rejected("这是系统软件，不能卸载") : .allowed
        }
        let parent = normalizedPath(target.deletingLastPathComponent())
        if scanRoots.contains(where: { normalizedPath($0) == parent }) {
            return .allowed
        }
        return .rejected("路径不在允许范围内")
    }
}
```

- [ ] **Step 8: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 405 tests … passed`，零警告。

- [ ] **Step 9: Commit**

```bash
git add Package.swift Sources/UninstallerModule Tests/UninstallerModuleTests
git commit -m "feat(uninstaller): module target, app identity from Info.plist, protection rules with path re-validation"
```

---

### Task 2: 位置表、名字匹配、残留扫描

**Files:**
- Create: `Sources/UninstallerModule/ScanLocation.swift`, `Sources/UninstallerModule/LeftoverMatcher.swift`, `Sources/UninstallerModule/LeftoverScanner.swift`
- Test: `Tests/UninstallerModuleTests/LeftoverMatcherTests.swift`, `Tests/UninstallerModuleTests/ScanLocationTests.swift`, `Tests/UninstallerModuleTests/LeftoverScannerTests.swift`

**Interfaces:**
- Consumes: `AppIdentity`、`ProtectionRules.normalizedPath` / `isForbiddenPath`、`TempDir`（Task 1）
- Produces:
  - `public struct ScanLocation: Equatable, Sendable { url; category: String; kind: Kind; isSystemLevel: Bool; isBackgroundService: Bool }`，`enum Kind { byIdentifier, byName, crashReports, hidden }`；`static func standard() -> [ScanLocation]`；`static func all(home:systemRoot:userCacheDirectory:userTempDirectory:) -> [ScanLocation]`
  - `public enum Confidence: Int { case certain, possible }`
  - `public enum LeftoverMatcher { static func match(fileName:kind:identity:otherBundleIDs:) -> Confidence? }`
  - `public struct LeftoverItem: Identifiable, Equatable, Sendable { url; category; confidence; needsAdmin; isAppBundle; isBackgroundService; var sizeBytes: UInt64?; id = url.path }`
  - `public struct LeftoverScanResult { var items: [LeftoverItem]; var unreadableLocations: [URL] }`
  - `public struct LeftoverScanner: Sendable { init(locations:home:); static func standard(); var scanRoots: [URL]; func scan(identity:otherBundleIDs:isCancelled:) -> LeftoverScanResult }`

匹配规则相对设计文档 §3.3 的细化（都是为了少误报）：包含匹配要求"完整的词"（卸载 Code 不牵连 Xcode）；`com.apple.` 开头的名字一律不碰；名字如果更具体地指向**另一个已安装软件**的 bundle id（卸载 Chrome 时遇到 `com.google.Chrome.canary`）就不算；崩溃报告规则只在崩溃报告目录里生效。扫描器是只读的：只列一级子项的名字，不改任何东西。

- [ ] **Step 1: 写失败的测试 `Tests/UninstallerModuleTests/LeftoverMatcherTests.swift`**

```swift
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
```

- [ ] **Step 2: 写失败的测试 `Tests/UninstallerModuleTests/ScanLocationTests.swift`**

```swift
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
```

- [ ] **Step 3: 写失败的测试 `Tests/UninstallerModuleTests/LeftoverScannerTests.swift`**

```swift
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
```

- [ ] **Step 4: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'LeftoverMatcher' in scope` / `cannot find 'ScanLocation' in scope`。

- [ ] **Step 5: 写 `Sources/UninstallerModule/ScanLocation.swift`**

注意局部函数叫 `userLevel` / `systemLevel` —— 不要起名 `system`，那会触发 Task 4 的源码扫描（它禁止 C 的 `system()` 调用）。

```swift
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
```

- [ ] **Step 6: 写 `Sources/UninstallerModule/LeftoverMatcher.swift`**

```swift
import Foundation

/// 一个文件和待卸载软件的关系有多确定。
public enum Confidence: Int, Sendable, Equatable {
    /// 确定相关：名字里带着这个软件独有的标识，默认勾选
    case certain
    /// 可能相关：只是同名或名字沾边，默认不勾选，由用户自己判断
    case possible
}

/// 只看名字的匹配规则。纯函数，不碰文件系统。
public enum LeftoverMatcher {
    /// 比较前先去掉的后缀（小写）
    static let strippedSuffixes = [".plist", ".savedstate", ".binarycookies", ".bom", ".log", ".crash", ".ips", ".diag"]

    /// - otherBundleIDs: 机器上**其他**已安装软件的 bundle id。名字如果更像是它们的东西
    ///   （例如卸载 Chrome 时遇到 com.google.Chrome.canary 的文件），就不算在这个软件头上。
    public static func match(
        fileName: String,
        kind: ScanLocation.Kind,
        identity: AppIdentity,
        otherBundleIDs: Set<String> = []
    ) -> Confidence? {
        var name = fileName.lowercased()
        for suffix in strippedSuffixes where name.hasSuffix(suffix) && name.count > suffix.count {
            name.removeLast(suffix.count)
            break
        }
        guard !name.isEmpty else { return nil }
        if name.hasPrefix("com.apple.") { return nil }                 // Apple 自己的数据永远不碰

        let bundleID = identity.bundleID?.lowercased()
        if belongsToAnotherApp(name, own: bundleID, others: otherBundleIDs) { return nil }

        // —— 确定相关 ——
        if let bundleID {
            if name == bundleID || name.hasPrefix(bundleID + ".") { return .certain }
            if name.hasSuffix("." + bundleID) || name.contains("." + bundleID + ".") { return .certain }
        }
        if kind == .byName, identity.nameVariants.contains(name) { return .certain }
        if kind == .crashReports,
           identity.nameVariants.contains(where: { name.hasPrefix($0 + "_") || name.hasPrefix($0 + "-") }) {
            return .certain
        }

        // —— 可能相关 ——
        let bare = name.hasPrefix(".") ? String(name.dropFirst()) : name
        if kind == .hidden, identity.nameVariants.contains(bare) { return .possible }
        if let vendor = identity.vendorFragment, bare == vendor { return .possible }
        if let segment = identity.lastIDSegment, containsWord(name, segment) { return .possible }
        if identity.nameVariants.contains(where: { $0.count >= 4 && containsWord(name, $0) }) { return .possible }
        return nil
    }

    /// word 是否作为一个"完整的词"出现在 text 里：前后不能紧挨着字母或数字。
    /// 这样卸载 "Code" 时不会把 "Xcode" 的东西列出来。
    static func containsWord(_ text: String, _ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        var searchStart = text.startIndex
        while let range = text.range(of: word, range: searchStart..<text.endIndex) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            let boundedBefore = before.map { !($0.isLetter || $0.isNumber) } ?? true
            let boundedAfter = after.map { !($0.isLetter || $0.isNumber) } ?? true
            if boundedBefore && boundedAfter { return true }
            searchStart = text.index(after: range.lowerBound)
        }
        return false
    }

    /// 名字是否更具体地指向另一个已安装的软件。
    static func belongsToAnotherApp(_ name: String, own: String?, others: Set<String>) -> Bool {
        for other in others {
            let otherID = other.lowercased()
            if otherID == own || otherID.isEmpty { continue }
            let matchesOther = name == otherID || name.hasPrefix(otherID + ".")
                || name.hasSuffix("." + otherID) || name.contains("." + otherID + ".")
            guard matchesOther else { continue }
            // 另一个软件的 id 比自己的更长（更具体），或者自己的 id 根本不出现在名字里 → 归它
            if let own, name.contains(own), otherID.count <= own.count { continue }
            return true
        }
        return false
    }
}
```

- [ ] **Step 7: 写 `Sources/UninstallerModule/LeftoverScanner.swift`**

```swift
import Foundation

/// 清单里的一条：软件本体，或者某个扫描位置下的一个文件 / 文件夹。
public struct LeftoverItem: Identifiable, Equatable, Sendable {
    public let url: URL
    public let category: String
    public let confidence: Confidence
    /// 当前用户没有权限移动它，需要交给访达（系统会弹管理员密码框）
    public let needsAdmin: Bool
    public let isAppBundle: Bool
    public let isBackgroundService: Bool
    public var sizeBytes: UInt64?

    public var id: String { url.path }

    public init(url: URL, category: String, confidence: Confidence, needsAdmin: Bool,
                isAppBundle: Bool = false, isBackgroundService: Bool = false, sizeBytes: UInt64? = nil) {
        self.url = url
        self.category = category
        self.confidence = confidence
        self.needsAdmin = needsAdmin
        self.isAppBundle = isAppBundle
        self.isBackgroundService = isBackgroundService
        self.sizeBytes = sizeBytes
    }
}

public struct LeftoverScanResult: Equatable, Sendable {
    public var items: [LeftoverItem]
    /// 存在但无权读取的位置（例如没有"完全磁盘访问权限"时的容器目录）
    public var unreadableLocations: [URL]

    public init(items: [LeftoverItem] = [], unreadableLocations: [URL] = []) {
        self.items = items
        self.unreadableLocations = unreadableLocations
    }
}

/// 在各个扫描位置的**一级**子项里找出和某个软件相关的东西。只读，不改动任何文件。
public struct LeftoverScanner: Sendable {
    public let locations: [ScanLocation]
    public let home: URL

    public init(locations: [ScanLocation], home: URL) {
        self.locations = locations
        self.home = home
    }

    public static func standard() -> LeftoverScanner {
        LeftoverScanner(locations: ScanLocation.standard(), home: FileManager.default.homeDirectoryForCurrentUser)
    }

    public var scanRoots: [URL] { locations.map(\.url) }

    public func scan(
        identity: AppIdentity,
        otherBundleIDs: Set<String> = [],
        isCancelled: () -> Bool = { false }
    ) -> LeftoverScanResult {
        let fileManager = FileManager.default
        let roots = scanRoots
        var result = LeftoverScanResult()
        var seen = Set<String>()

        // 软件本体永远排第一条
        result.items.append(LeftoverItem(
            url: identity.url, category: "软件本体", confidence: .certain,
            needsAdmin: Self.needsAdmin(identity.url), isAppBundle: true))
        seen.insert(ProtectionRules.normalizedPath(identity.url))

        for location in locations {
            if isCancelled() { return result }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: location.url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue                                        // 位置不存在：跳过
            }
            guard let names = try? fileManager.contentsOfDirectory(atPath: location.url.path) else {
                result.unreadableLocations.append(location.url)   // 存在但读不了
                continue
            }
            for name in names {
                // 主目录这个位置只看隐藏项；普通文件夹（文稿、下载……）不归卸载器管
                if location.kind == .hidden, ProtectionRules.normalizedPath(location.url) == ProtectionRules.normalizedPath(home),
                   !name.hasPrefix(".") {
                    continue
                }
                guard let confidence = LeftoverMatcher.match(
                    fileName: name, kind: location.kind, identity: identity, otherBundleIDs: otherBundleIDs)
                else { continue }

                let url = location.url.appendingPathComponent(name)
                if ProtectionRules.isForbiddenPath(url, home: home, scanRoots: roots) { continue }
                guard seen.insert(ProtectionRules.normalizedPath(url)).inserted else { continue }

                result.items.append(LeftoverItem(
                    url: url, category: location.category, confidence: confidence,
                    needsAdmin: Self.needsAdmin(url), isBackgroundService: location.isBackgroundService))
            }
        }
        return result
    }

    /// 移到废纸篓需要：能改父目录；如果它自己是目录，还要能改它自己（搬目录要更新它的 ".."）。
    static func needsAdmin(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        let parent = url.deletingLastPathComponent().path
        if !fileManager.isWritableFile(atPath: parent) { return true }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values?.isDirectory == true, values?.isSymbolicLink != true, !fileManager.isWritableFile(atPath: url.path) {
            return true
        }
        return false
    }
}
```

- [ ] **Step 8: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 433 tests … passed`，零警告。

- [ ] **Step 9: Commit**

```bash
git add Sources/UninstallerModule Tests/UninstallerModuleTests
git commit -m "feat(uninstaller): scan location table, name-based leftover matcher, read-only leftover scanner"
```

---

### Task 3: 已安装软件、大小计算、搜索排序

**Files:**
- Create: `Sources/UninstallerModule/InstalledAppScanner.swift`, `Sources/UninstallerModule/SizeCalculator.swift`, `Sources/UninstallerModule/AppListing.swift`
- Test: `Tests/UninstallerModuleTests/InstalledAppScannerTests.swift`, `Tests/UninstallerModuleTests/SizeAndListingTests.swift`

**Interfaces:**
- Consumes: `AppIdentity`、`ProtectionRules`、`TempDir`（Task 1）
- Produces:
  - `public struct InstalledApp: Identifiable, Equatable, Sendable { identity: AppIdentity; title: String; var sizeBytes: UInt64?; id = identity.url.path }`；`init(identity:title:sizeBytes:)`；`init?(appURL:)`
  - `public struct InstalledAppList { var apps: [InstalledApp]; var allBundleIDs: Set<String> }`（`allBundleIDs` 含受保护的软件，供匹配器排除"别的软件的文件"）
  - `public struct InstalledAppScanner: Sendable { init(roots:); static func standard(); func scan() -> InstalledAppList }`
  - `public enum SizeCalculator { static func allocatedSize(of:isCancelled:) -> UInt64?; static func format(_:) -> String }`
  - `public enum AppListing { enum SortOrder { name, size }（带中文 title）; static func filter(_:query:); static func sorted(_:by:) }`

- [ ] **Step 1: 写失败的测试 `Tests/UninstallerModuleTests/InstalledAppScannerTests.swift`**

```swift
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
```

- [ ] **Step 2: 写失败的测试 `Tests/UninstallerModuleTests/SizeAndListingTests.swift`**

```swift
import Foundation
import Testing
@testable import UninstallerModule

@Suite struct SizeCalculatorTests {
    @Test func directorySizeCoversNestedFiles() throws {
        let temp = try TempDir()
        try temp.makeFile("Big/a.bin", bytes: 200_000)
        try temp.makeFile("Big/nested/deeper/b.bin", bytes: 300_000)

        let size = try #require(SizeCalculator.allocatedSize(of: temp.url.appendingPathComponent("Big")))

        #expect(size >= 500_000)
        #expect(size < 2_000_000)                     // 按块分配会略大于内容，但不会离谱
    }

    @Test func singleFileAndMissingPath() throws {
        let temp = try TempDir()
        let file = try temp.makeFile("one.bin", bytes: 100_000)

        let fileSize = try #require(SizeCalculator.allocatedSize(of: file))
        #expect(fileSize >= 100_000)
        #expect(SizeCalculator.allocatedSize(of: temp.url.appendingPathComponent("missing")) == 0)
    }

    @Test func symlinksAreNotFollowed() throws {
        let temp = try TempDir()
        try temp.makeFile("Target/huge.bin", bytes: 900_000)
        try temp.makeDirectory("Holder")
        try FileManager.default.createSymbolicLink(
            at: temp.url.appendingPathComponent("Holder/link"), withDestinationURL: temp.url.appendingPathComponent("Target"))

        let size = try #require(SizeCalculator.allocatedSize(of: temp.url.appendingPathComponent("Holder")))

        #expect(size < 100_000)
    }

    @Test func cancellationReturnsNil() throws {
        let temp = try TempDir()
        for index in 0..<300 {
            try temp.makeFile("Many/file-\(index).bin", bytes: 8)
        }
        #expect(SizeCalculator.allocatedSize(of: temp.url.appendingPathComponent("Many"), isCancelled: { true }) == nil)
    }

    @Test func formatting() {
        let kilobyte: UInt64 = 1024
        let megabyte: UInt64 = 1_048_576
        let gigabyte: UInt64 = 1_073_741_824
        #expect(SizeCalculator.format(0) == "0 KB")
        #expect(SizeCalculator.format(100) == "1 KB")
        #expect(SizeCalculator.format(4 * kilobyte) == "4 KB")
        #expect(SizeCalculator.format(850 * megabyte) == "850 MB")
        #expect(SizeCalculator.format(gigabyte) == "1.0 GB")
        #expect(SizeCalculator.format(gigabyte * 23 / 10) == "2.3 GB")
    }
}

@Suite struct AppListingTests {
    private func app(_ title: String, id: String, size: UInt64?) -> InstalledApp {
        InstalledApp(
            identity: AppIdentity(url: URL(fileURLWithPath: "/Applications/\(title).app"), bundleID: id, names: [title]),
            title: title, sizeBytes: size)
    }

    @Test func searchMatchesTitleNameAndBundleIdentifier() {
        let apps = [app("微信", id: "com.tencent.xinWeChat", size: nil), app("Google Chrome", id: "com.google.Chrome", size: nil)]

        #expect(AppListing.filter(apps, query: "").count == 2)
        #expect(AppListing.filter(apps, query: "  ").count == 2)
        #expect(AppListing.filter(apps, query: "微").map(\.title) == ["微信"])
        #expect(AppListing.filter(apps, query: "chrome").map(\.title) == ["Google Chrome"])
        #expect(AppListing.filter(apps, query: "TENCENT").map(\.title) == ["微信"])
        #expect(AppListing.filter(apps, query: "nothing").isEmpty)
    }

    @Test func sortByNameUsesNaturalOrder() {
        let apps = [app("Tool 10", id: "a.b.c10", size: nil), app("tool 2", id: "a.b.c2", size: nil), app("Alpha", id: "a.b.alpha", size: nil)]
        #expect(AppListing.sorted(apps, by: .name).map(\.title) == ["Alpha", "tool 2", "Tool 10"])
    }

    @Test func sortBySizePutsBiggestFirstAndUnknownLast() {
        let apps = [
            app("Small", id: "a.b.small", size: 10), app("Pending", id: "a.b.pending", size: nil),
            app("Big", id: "a.b.big", size: 900), app("Also Pending", id: "a.b.also", size: nil),
        ]
        #expect(AppListing.sorted(apps, by: .size).map(\.title) == ["Big", "Small", "Also Pending", "Pending"])
    }

    @Test func sortOrderTitlesAreChinese() {
        #expect(AppListing.SortOrder.allCases.map(\.title) == ["名称", "大小"])
    }
}
```

- [ ] **Step 3: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'InstalledAppScanner' in scope`。

- [ ] **Step 4: 写 `Sources/UninstallerModule/InstalledAppScanner.swift`**

```swift
import Foundation

/// 软件列表里的一行。
public struct InstalledApp: Identifiable, Equatable, Sendable {
    public let identity: AppIdentity
    /// 列表里显示的名字（系统给的本地化名字，例如"微信"）
    public let title: String
    /// 占用空间；nil = 还没算好
    public var sizeBytes: UInt64?

    public var id: String { identity.url.path }

    public init(identity: AppIdentity, title: String, sizeBytes: UInt64? = nil) {
        self.identity = identity
        self.title = title
        self.sizeBytes = sizeBytes
    }

    /// 从一个 .app 路径构造；不是正常的软件时返回 nil。
    public init?(appURL: URL) {
        guard let identity = AppIdentity(appURL: appURL) else { return nil }
        self.init(identity: identity, title: Self.title(for: appURL, fallback: identity.displayName))
    }

    static func title(for url: URL, fallback: String) -> String {
        var name = FileManager.default.displayName(atPath: url.path)
        if name.lowercased().hasSuffix(".app") { name.removeLast(4) }
        return name.isEmpty ? fallback : name
    }
}

public struct InstalledAppList: Equatable, Sendable {
    /// 可以卸载的软件（受保护的已经排除）
    public var apps: [InstalledApp]
    /// 扫到的**全部**软件的 bundle id（含受保护的），用来避免误认别的软件的文件
    public var allBundleIDs: Set<String>

    public init(apps: [InstalledApp] = [], allBundleIDs: Set<String> = []) {
        self.apps = apps
        self.allBundleIDs = allBundleIDs
    }
}

/// 列出已安装的软件：各个根目录本身，以及它们的一级子文件夹。不进入 .app 内部。
public struct InstalledAppScanner: Sendable {
    public let roots: [URL]

    public init(roots: [URL]) {
        self.roots = roots
    }

    public static func standard() -> InstalledAppScanner {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return InstalledAppScanner(roots: [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
        ])
    }

    public func scan() -> InstalledAppList {
        var list = InstalledAppList()
        var seen = Set<String>()
        for root in roots {
            for child in children(of: root) {
                if child.pathExtension.lowercased() == "app" {
                    add(child, to: &list, seen: &seen)
                } else if isPlainDirectory(child) {
                    for grandchild in children(of: child) where grandchild.pathExtension.lowercased() == "app" {
                        add(grandchild, to: &list, seen: &seen)
                    }
                }
            }
        }
        return list
    }

    private func add(_ url: URL, to list: inout InstalledAppList, seen: inout Set<String>) {
        guard seen.insert(ProtectionRules.normalizedPath(url)).inserted else { return }
        guard let app = InstalledApp(appURL: url) else { return }
        if let bundleID = app.identity.bundleID { list.allBundleIDs.insert(bundleID) }
        if ProtectionRules.isProtectedApp(url: url, bundleID: app.identity.bundleID) { return }
        list.apps.append(app)
    }

    private func children(of directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.sorted().map { directory.appendingPathComponent($0) }
    }

    private func isPlainDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true && values?.isPackage != true
    }
}
```

- [ ] **Step 5: 写 `Sources/UninstallerModule/SizeCalculator.swift`**

```swift
import Foundation

public enum SizeCalculator {
    /// 一个文件或整个目录实际占用的磁盘空间。不跟随符号链接。被取消时返回 nil。
    public static func allocatedSize(of url: URL, isCancelled: () -> Bool = { false }) -> UInt64? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory != true || values.isSymbolicLink == true {
            return UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true })
        else { return 0 }

        var total: UInt64 = 0
        var visited = 0
        for case let item as URL in enumerator {
            visited += 1
            if visited % 256 == 0, isCancelled() { return nil }
            guard let itemValues = try? item.resourceValues(forKeys: keys) else { continue }
            total += UInt64(itemValues.totalFileAllocatedSize ?? itemValues.fileAllocatedSize ?? 0)
        }
        return isCancelled() ? nil : total
    }

    /// "3.2 GB" / "850 MB" / "12 KB"（1 GB = 1024³ 字节，与系统监控的写法一致）。
    public static func format(_ bytes: UInt64) -> String {
        let kilobyte = 1024.0
        let megabyte = kilobyte * 1024
        let gigabyte = megabyte * 1024
        let value = Double(bytes)
        if value >= gigabyte {
            return String(format: "%.1f GB", value / gigabyte)
        }
        if value >= megabyte {
            return String(format: "%.0f MB", value / megabyte)
        }
        if bytes == 0 {
            return "0 KB"
        }
        return String(format: "%.0f KB", max(1, (value / kilobyte).rounded()))
    }
}
```

- [ ] **Step 6: 写 `Sources/UninstallerModule/AppListing.swift`**

```swift
import Foundation

/// 软件列表的搜索和排序。纯函数。
public enum AppListing {
    public enum SortOrder: String, CaseIterable, Identifiable, Sendable {
        case name
        case size

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .name: return "名称"
            case .size: return "大小"
            }
        }
    }

    /// 按显示名、软件名和 bundle id 做不区分大小写的包含匹配。空查询 = 全部。
    public static func filter(_ apps: [InstalledApp], query: String) -> [InstalledApp] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return apps }
        return apps.filter { app in
            app.title.lowercased().contains(needle)
                || app.identity.displayName.lowercased().contains(needle)
                || (app.identity.bundleID?.lowercased().contains(needle) ?? false)
        }
    }

    /// 名称：按本地化规则比较；大小：大的在前，还没算好的排最后。相同时按名称，保证顺序稳定。
    public static func sorted(_ apps: [InstalledApp], by order: SortOrder) -> [InstalledApp] {
        apps.sorted { first, second in
            if order == .size, first.sizeBytes != second.sizeBytes {
                switch (first.sizeBytes, second.sizeBytes) {
                case let (a?, b?): return a > b
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): break
                }
            }
            let comparison = first.title.localizedStandardCompare(second.title)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return first.id < second.id
        }
    }
}
```

- [ ] **Step 7: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 449 tests … passed`，零警告。

- [ ] **Step 8: Commit**

```bash
git add Sources/UninstallerModule Tests/UninstallerModuleTests
git commit -m "feat(uninstaller): installed app scanner, cancellable size calculator, list search and sorting"
```

---

### Task 4: 移到废纸篓（Trasher）—— 只用假执行器测试

**Files:**
- Create: `Sources/UninstallerModule/Trasher.swift`, `Sources/UninstallerModule/SystemTrashers.swift`
- Test: `Tests/UninstallerModuleTests/TrasherTests.swift`

**Interfaces:**
- Consumes: `LeftoverItem`（Task 2）、`AppIdentity`、`ProtectionRules.checkRemoval`（Task 1）、`SizeCalculator.format`（Task 3）
- Produces:
  - `public protocol FileTrashing: Sendable { func trash(_ url: URL) throws }`
  - `public protocol PrivilegedTrashing: Sendable { func trash(_ urls: [URL]) -> PrivilegedTrashOutcome }`；`enum PrivilegedTrashOutcome { completed, automationDenied, userCancelled, failed(String) }`
  - `public struct TrashFailure { item; reason }`；`public struct TrashReport { succeeded; failed; appManagementBlocked; automationDenied; freedBytes; touchedBackgroundServices; removedAppBundle; summary }`
  - `public struct Trasher: Sendable { init(direct:privileged:scanRoots:home:stillExists:); func run(items:app:) -> TrashReport }`
  - 正式执行器：`DirectTrasher: FileTrashing`（`FileManager.trashItem`）、`FinderTrasher: PrivilegedTrashing`（`NSAppleScript` 让访达 `delete`；`static func script(for:)`、`static func escape(_:)`）

流程：逐项先复核 → 直接移 → 权限错误的攒成一批，**只调用一次**有权限的执行器 → 执行后用 `stillExists` 逐项核对是否真的被移走。

**再次强调**：本任务的测试里只有假执行器，任何测试都不会触发 `DirectTrasher` 或 `FinderTrasher`。不要写"真的移一个临时文件到废纸篓试试"之类的测试。

- [ ] **Step 1: 写失败的测试 `Tests/UninstallerModuleTests/TrasherTests.swift`**

```swift
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
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find type 'FileTrashing' in scope`。

- [ ] **Step 3: 写 `Sources/UninstallerModule/Trasher.swift`**

```swift
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
```

- [ ] **Step 4: 写 `Sources/UninstallerModule/SystemTrashers.swift`**

```swift
import Foundation

/// 正式实现之一：用系统接口把文件移到废纸篓（可以从废纸篓"放回原处"）。
public struct DirectTrasher: FileTrashing {
    public init() {}

    public func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

/// 正式实现之二：请访达把文件移到废纸篓。访达有权限处理属于系统的文件，
/// 需要时由它自己弹出管理员密码框 —— MyKit 不接触密码。
public struct FinderTrasher: PrivilegedTrashing {
    public init() {}

    public func trash(_ urls: [URL]) -> PrivilegedTrashOutcome {
        guard !urls.isEmpty else { return .completed }
        guard let script = NSAppleScript(source: Self.script(for: urls)) else {
            return .failed("无法生成给访达的指令")
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return .completed }

        let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
        switch code {
        case -1743: return .automationDenied            // errAEEventNotPermitted：没有"自动化"授权
        case -128: return .userCancelled                // userCanceledErr
        default:
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "错误 \(code)"
            return .failed(message)
        }
    }

    /// 生成给访达的指令。路径作为字符串字面量传入，先转义反斜杠和双引号；不经过 shell。
    static func script(for urls: [URL]) -> String {
        let files = urls.map { "POSIX file \"\(escape($0.path))\"" }.joined(separator: ", ")
        return "tell application \"Finder\" to delete {\(files)}"
    }

    static func escape(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 460 tests … passed`，零警告。如果 `NoPermanentDeleteTests` 失败，它会指出哪个文件里出现了哪个禁用的词 —— 改掉那个词（包括注释和函数名），不要改测试。

- [ ] **Step 6: Commit**

```bash
git add Sources/UninstallerModule Tests/UninstallerModuleTests
git commit -m "feat(uninstaller): trasher with re-validation, single privileged batch via Finder, report model; no-permanent-delete source scan"
```

---

### Task 5: 视图模型

**Files:**
- Create: `Sources/UninstallerModule/UninstallerDependencies.swift`, `Sources/UninstallerModule/UninstallerViewModel.swift`
- Test: `Tests/UninstallerModuleTests/UninstallerViewModelTests.swift`

**Interfaces:**
- Consumes: Task 1–4 的全部公开类型
- Produces:
  - `public struct UninstallerDependencies { listApps; scanLeftovers; sizeOf; makeApp; isProtected; isRunning; quit; trash; static func live() }`（签名见文件）
  - `@MainActor enum RunningAppControl`（`isRunning`、`quit(_:timeout:)` —— 只用 `terminate()` 正常退出）、`final class CancellationFlag`、`public enum PathDisplay { abbreviated(_:home:), location(of:home:) }`
  - `@MainActor public final class UninstallerViewModel: ObservableObject`：
    - 状态：`apps`、`query`、`sortOrder`、`isLoadingApps`、`selectedApp`、`items`、`checkedIDs`、`highlightedItemID`、`unreadableLocations`、`phase`、`notice`
    - `enum Phase { idle, scanning, ready, needsQuit, quitting, confirming, running, finished(TrashReport) }`
    - `visibleApps`、`groups`（确定相关 / 可能相关 / 需要管理员密码）、`checkedItems`、`checkedBytes`、`summaryText`、`confirmationText`、`canUninstall`、`highlightedItem`
    - `start()`、`load() async`、`computeAppSizes() async`、`select(_:) async`、`isChecked(_:)`、`setChecked(_:_:)`、`selectAll()`、`selectOnlyCertain()`、`requestUninstall()`、`quitAndContinue() async`、`quitTapped()`、`cancelPending()`、`confirm() async`、`confirmTapped()`、`dismissResult() async`、`handleDrop(_:) async -> Bool`、`teardown()`

`confirmTapped()` / `quitTapped()` 是给界面按钮用的同步入口：点下去的同一时刻 `phase` 就变了，由状态驱动的提示框不会因为"状态还没变"而重复弹出。

- [ ] **Step 1: 写失败的测试 `Tests/UninstallerModuleTests/UninstallerViewModelTests.swift`**

```swift
import Foundation
import Testing
@testable import UninstallerModule

/// 记录假执行器收到的调用，并让测试控制每个假操作的返回值。
private final class FakeSystem: @unchecked Sendable {
    private let lock = NSLock()
    private var _trashCalls: [[String]] = []
    private var _quitCalls = 0

    var list = InstalledAppList()
    var leftovers: [String: LeftoverScanResult] = [:]          // 键：软件路径
    var scanDelays: [String: TimeInterval] = [:]
    var sizes: [String: UInt64] = [:]                          // 键：文件名
    var running = false
    var quitSucceeds = true
    var report = TrashReport()
    var protectedBundleIDs: Set<String> = ["com.apple.Safari"]

    var trashCalls: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return _trashCalls
    }

    var quitCalls: Int {
        lock.lock(); defer { lock.unlock() }
        return _quitCalls
    }

    func recordTrash(_ items: [LeftoverItem]) {
        lock.lock(); defer { lock.unlock() }
        _trashCalls.append(items.map(\.url.lastPathComponent))
    }

    func recordQuit() {
        lock.lock(); defer { lock.unlock() }
        _quitCalls += 1
    }

    func dependencies() -> UninstallerDependencies {
        UninstallerDependencies(
            listApps: { self.list },
            scanLeftovers: { identity, _, _ in
                if let delay = self.scanDelays[identity.url.path] { Thread.sleep(forTimeInterval: delay) }
                return self.leftovers[identity.url.path] ?? LeftoverScanResult()
            },
            sizeOf: { url, _ in self.sizes[url.lastPathComponent] },
            makeApp: { url in
                InstalledApp(
                    identity: AppIdentity(url: url, bundleID: url.lastPathComponent.hasPrefix("Safari") ? "com.apple.Safari" : "org.example.dropped",
                                          names: [url.deletingPathExtension().lastPathComponent]),
                    title: url.deletingPathExtension().lastPathComponent)
            },
            isProtected: { _, bundleID in bundleID.map { self.protectedBundleIDs.contains($0) } ?? false },
            isRunning: { _ in self.running },
            quit: { _ in
                self.recordQuit()
                return self.quitSucceeds
            },
            trash: { items, _ in
                self.recordTrash(items)
                return self.report
            }
        )
    }
}

@MainActor
@Suite struct UninstallerViewModelTests {
    private func app(_ name: String, id: String, size: UInt64? = nil) -> InstalledApp {
        InstalledApp(
            identity: AppIdentity(url: URL(fileURLWithPath: "/Applications/\(name).app"), bundleID: id, names: [name]),
            title: name, sizeBytes: size)
    }

    private func item(_ path: String, _ confidence: Confidence = .certain, admin: Bool = false, isApp: Bool = false) -> LeftoverItem {
        LeftoverItem(url: URL(fileURLWithPath: path), category: "测试", confidence: confidence, needsAdmin: admin, isAppBundle: isApp)
    }

    /// 一个装了 Tool 和 Other 两个软件的世界；Tool 有 4 条相关项。
    private func makeWorld() -> (FakeSystem, UninstallerViewModel, InstalledApp, InstalledApp) {
        let system = FakeSystem()
        let tool = app("Tool", id: "org.example.tool")
        let other = app("Other", id: "org.example.other")
        system.list = InstalledAppList(apps: [tool, other], allBundleIDs: ["org.example.tool", "org.example.other", "com.apple.Safari"])
        system.leftovers[tool.id] = LeftoverScanResult(items: [
            item("/Applications/Tool.app", isApp: true),
            item("/Users/t/Library/Preferences/org.example.tool.plist"),
            item("/Users/t/.tool", .possible),
            item("/Library/LaunchDaemons/org.example.tool.plist", admin: true),
        ], unreadableLocations: [URL(fileURLWithPath: "/Users/t/Library/Containers")])
        system.leftovers[other.id] = LeftoverScanResult(items: [item("/Applications/Other.app", isApp: true)])
        system.sizes = ["Tool.app": 1_048_576 * 300, "org.example.tool.plist": 4096, ".tool": 1_048_576 * 35, "Other.app": 1_048_576 * 10]
        return (system, UninstallerViewModel(dependencies: system.dependencies()), tool, other)
    }

    @Test func loadListsAppsThenSizesArriveOneByOne() async {
        let (_, vm, _, _) = makeWorld()

        await vm.load()
        #expect(vm.visibleApps.map(\.title) == ["Other", "Tool"])
        #expect(vm.visibleApps.allSatisfy { $0.sizeBytes == nil })
        #expect(!vm.isLoadingApps)

        await vm.computeAppSizes()
        vm.sortOrder = .size
        #expect(vm.visibleApps.map(\.title) == ["Tool", "Other"])
    }

    @Test func searchFiltersTheVisibleList() async {
        let (_, vm, _, _) = makeWorld()
        await vm.load()
        vm.query = "oth"
        #expect(vm.visibleApps.map(\.title) == ["Other"])
    }

    @Test func selectingAnAppScansGroupsAndChecksOnlyCertainItems() async {
        let (_, vm, tool, _) = makeWorld()
        await vm.load()

        await vm.select(tool)

        #expect(vm.phase == .ready)
        #expect(vm.groups.map(\.id) == ["certain", "possible", "admin"])
        #expect(vm.groups[0].items.map(\.url.lastPathComponent) == ["Tool.app", "org.example.tool.plist"])
        #expect(vm.groups[1].title == "可能相关（默认不勾选，请自己判断）")
        #expect(vm.checkedItems.map(\.url.lastPathComponent) == ["Tool.app", "org.example.tool.plist", "org.example.tool.plist"])
        #expect(!vm.isChecked(vm.groups[1].items[0]))
        #expect(vm.unreadableLocations.map(\.lastPathComponent) == ["Containers"])
        #expect(vm.summaryText == "已选 3 项，300 MB")
    }

    @Test func checkboxesSelectAllAndOnlyCertain() async throws {
        let (_, vm, tool, _) = makeWorld()
        await vm.load()
        await vm.select(tool)
        let hidden = try #require(vm.items.first { $0.url.lastPathComponent == ".tool" })

        vm.setChecked(hidden, true)
        #expect(vm.summaryText == "已选 4 项，335 MB")

        vm.selectOnlyCertain()
        #expect(vm.checkedItems.count == 3)

        vm.selectAll()
        #expect(vm.checkedItems.count == 4)

        for entry in vm.items { vm.setChecked(entry, false) }
        #expect(!vm.canUninstall)
        #expect(vm.summaryText == "已选 0 项，0 KB")
    }

    @Test func selectingAnotherAppDropsTheSlowerPreviousScan() async throws {
        let (system, vm, tool, other) = makeWorld()
        await vm.load()
        system.scanDelays[tool.id] = 0.3

        let slow = Task { await vm.select(tool) }
        try await Task.sleep(nanoseconds: 50_000_000)
        await vm.select(other)
        await slow.value

        #expect(vm.selectedApp?.title == "Other")
        #expect(vm.items.map(\.url.lastPathComponent) == ["Other.app"])
        #expect(vm.phase == .ready)
    }

    @Test func knownAppSizeIsReusedForTheBundleRow() async {
        let (system, vm, _, _) = makeWorld()
        let sized = app("Tool", id: "org.example.tool", size: 777)
        system.list.apps = [sized]
        system.sizes["Tool.app"] = 999_999
        await vm.load()

        await vm.select(sized)

        #expect(vm.items.first { $0.isAppBundle }?.sizeBytes == 777)
    }

    @Test func uninstallAsksForConfirmationThenTrashesCheckedItemsOnly() async {
        let (system, vm, tool, _) = makeWorld()
        await vm.load()
        await vm.select(tool)
        var report = TrashReport()
        report.succeeded = vm.checkedItems
        system.report = report

        vm.requestUninstall()
        #expect(vm.phase == .confirming)
        #expect(vm.confirmationText == "将把 3 项（300 MB）移到废纸篓。可以从废纸篓恢复。")
        #expect(system.trashCalls.isEmpty)                         // 确认之前什么都不动

        await vm.confirm()

        #expect(system.trashCalls == [["Tool.app", "org.example.tool.plist", "org.example.tool.plist"]])
        #expect(vm.phase == .finished(report))
    }

    @Test func cancellingTheConfirmationChangesNothing() async {
        let (system, vm, tool, _) = makeWorld()
        await vm.load()
        await vm.select(tool)

        vm.requestUninstall()
        vm.cancelPending()
        await vm.confirm()                                         // 不在确认状态：无效

        #expect(vm.phase == .ready)
        #expect(system.trashCalls.isEmpty)
    }

    @Test func runningAppMustQuitFirst() async {
        let (system, vm, tool, _) = makeWorld()
        system.running = true
        await vm.load()
        await vm.select(tool)

        vm.requestUninstall()
        #expect(vm.phase == .needsQuit)

        await vm.quitAndContinue()
        #expect(system.quitCalls == 1)
        #expect(vm.phase == .confirming)
    }

    @Test func appThatRefusesToQuitStopsTheFlowWithANotice() async {
        let (system, vm, tool, _) = makeWorld()
        system.running = true
        system.quitSucceeds = false
        await vm.load()
        await vm.select(tool)

        vm.requestUninstall()
        await vm.quitAndContinue()

        #expect(vm.phase == .ready)
        #expect(vm.notice == "「Tool」没有退出，请手动退出它之后再试")
        #expect(system.trashCalls.isEmpty)
    }

    @Test func runningCheckIsSkippedWhenTheAppItselfIsNotBeingRemoved() async throws {
        let (system, vm, tool, _) = makeWorld()
        system.running = true
        await vm.load()
        await vm.select(tool)
        let bundle = try #require(vm.items.first { $0.isAppBundle })

        vm.setChecked(bundle, false)                               // 只清残留，不删本体
        vm.requestUninstall()

        #expect(vm.phase == .confirming)
    }

    @Test func afterRemovingTheAppItLeavesTheList() async {
        let (system, vm, tool, _) = makeWorld()
        await vm.load()
        await vm.select(tool)
        var report = TrashReport()
        report.succeeded = vm.checkedItems
        system.report = report
        vm.requestUninstall()
        await vm.confirm()

        await vm.dismissResult()

        #expect(vm.apps.map(\.title) == ["Other"])
        #expect(vm.selectedApp == nil)
        #expect(vm.items.isEmpty)
        #expect(vm.phase == .idle)
    }

    @Test func whenTheAppSurvivesTheListIsRescanned() async {
        let (system, vm, tool, _) = makeWorld()
        await vm.load()
        await vm.select(tool)
        var report = TrashReport()
        report.failed = [TrashFailure(item: vm.items[0], reason: "需要管理员密码，你取消了输入")]
        system.report = report
        vm.requestUninstall()
        await vm.confirm()

        await vm.dismissResult()

        #expect(vm.apps.count == 2)
        #expect(vm.selectedApp?.title == "Tool")
        #expect(vm.phase == .ready)
    }

    @Test func droppingAnAppSelectsItAndAddsItToTheList() async {
        let (system, vm, _, _) = makeWorld()
        await vm.load()
        let dropped = URL(fileURLWithPath: "/Users/t/Downloads/Dropped.app")
        system.leftovers[dropped.path] = LeftoverScanResult(items: [item(dropped.path, isApp: true)])

        let accepted = await vm.handleDrop(dropped)

        #expect(accepted)
        #expect(vm.selectedApp?.title == "Dropped")
        #expect(vm.apps.count == 3)
        #expect(vm.phase == .ready)
    }

    @Test func droppingASystemAppOrANonAppIsRefused() async {
        let (_, vm, _, _) = makeWorld()
        await vm.load()

        let safari = await vm.handleDrop(URL(fileURLWithPath: "/Applications/Safari.app"))
        #expect(safari)
        #expect(vm.notice == "这是系统软件，不能卸载")
        #expect(vm.selectedApp == nil)

        let document = await vm.handleDrop(URL(fileURLWithPath: "/Users/t/Documents/report.pdf"))
        #expect(!document)
    }

    @Test func teardownReleasesEverything() async {
        let (_, vm, tool, _) = makeWorld()
        await vm.load()
        await vm.select(tool)

        vm.teardown()

        #expect(vm.apps.isEmpty)
        #expect(vm.items.isEmpty)
        #expect(vm.selectedApp == nil)
        #expect(vm.phase == .idle)
    }
}

@Suite struct PathDisplayTests {
    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    @Test func homeIsAbbreviatedWithATilde() {
        #expect(PathDisplay.abbreviated(URL(fileURLWithPath: "/Users/tester/Library/Caches/x"), home: home) == "~/Library/Caches/x")
        #expect(PathDisplay.abbreviated(home, home: home) == "~")
        #expect(PathDisplay.abbreviated(URL(fileURLWithPath: "/Library/LaunchDaemons/x.plist"), home: home) == "/Library/LaunchDaemons/x.plist")
        #expect(PathDisplay.abbreviated(URL(fileURLWithPath: "/Users/tester2/file"), home: home) == "/Users/tester2/file")
    }

    @Test func locationIsTheParentFolder() {
        #expect(PathDisplay.location(of: URL(fileURLWithPath: "/Users/tester/.docker"), home: home) == "~")
        #expect(PathDisplay.location(of: URL(fileURLWithPath: "/Applications/Tool.app"), home: home) == "/Applications")
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'UninstallerDependencies' in scope`。

- [ ] **Step 3: 写 `Sources/UninstallerModule/UninstallerDependencies.swift`**

```swift
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
```

- [ ] **Step 4: 写 `Sources/UninstallerModule/UninstallerViewModel.swift`**

```swift
import Foundation
import SwiftUI

/// 卸载窗口背后的全部状态。所有会碰系统的操作都通过 UninstallerDependencies 注入。
@MainActor
public final class UninstallerViewModel: ObservableObject {
    public enum Phase: Equatable {
        /// 还没选软件
        case idle
        case scanning
        /// 清单已经列出，等用户决定
        case ready
        /// 目标软件正在运行，等用户同意退出它
        case needsQuit
        /// 已经请它退出，正在等
        case quitting
        /// 等用户在确认框里点"移到废纸篓"
        case confirming
        case running
        case finished(TrashReport)
    }

    public struct ItemGroup: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let items: [LeftoverItem]
    }

    @Published public private(set) var apps: [InstalledApp] = []
    @Published public var query = ""
    @Published public var sortOrder: AppListing.SortOrder = .name
    @Published public private(set) var isLoadingApps = false
    @Published public private(set) var selectedApp: InstalledApp?
    @Published public private(set) var items: [LeftoverItem] = []
    @Published public private(set) var checkedIDs: Set<String> = []
    /// 清单里当前高亮的那一行（「在访达中显示」针对它）
    @Published public var highlightedItemID: String?
    @Published public private(set) var unreadableLocations: [URL] = []
    @Published public private(set) var phase: Phase = .idle
    /// 窗口里的一行提示（拖进了系统软件、软件没能退出……）
    @Published public var notice: String?

    private let dependencies: UninstallerDependencies
    private var allBundleIDs: Set<String> = []
    private var selectionGeneration = 0
    private var scanFlag = CancellationFlag()
    private var appSizeFlag = CancellationFlag()
    private var isTornDown = false

    public init(dependencies: UninstallerDependencies) {
        self.dependencies = dependencies
    }

    // MARK: 软件列表

    public var visibleApps: [InstalledApp] {
        AppListing.sorted(AppListing.filter(apps, query: query), by: sortOrder)
    }

    /// 窗口打开时调用：先列出软件，再在后台逐个算大小。
    public func start() {
        Task {
            await load()
            await computeAppSizes()
        }
    }

    public func load() async {
        isLoadingApps = true
        let listApps = dependencies.listApps
        let list = await Task.detached(priority: .userInitiated) { listApps() }.value
        guard !isTornDown else { return }
        apps = list.apps
        allBundleIDs = list.allBundleIDs
        isLoadingApps = false
    }

    /// 逐个计算大小，算好一个显示一个。窗口关闭时停止。
    public func computeAppSizes() async {
        let flag = appSizeFlag
        let sizeOf = dependencies.sizeOf
        for app in apps where app.sizeBytes == nil {
            if flag.isCancelled { return }
            let url = app.identity.url
            let size = await Task.detached(priority: .utility) { sizeOf(url, { flag.isCancelled }) }.value
            if flag.isCancelled { return }
            if let size, let index = apps.firstIndex(where: { $0.id == app.id }) {
                apps[index].sizeBytes = size
            }
        }
    }

    // MARK: 选择与清单

    /// 选中一个软件并扫描它的相关文件。再次调用会取消上一次还没完成的扫描。
    public func select(_ app: InstalledApp?) async {
        scanFlag.cancel()
        let flag = CancellationFlag()
        scanFlag = flag
        selectionGeneration += 1
        let generation = selectionGeneration

        selectedApp = app
        items = []
        checkedIDs = []
        unreadableLocations = []
        highlightedItemID = nil
        notice = nil
        guard let app else {
            phase = .idle
            return
        }

        phase = .scanning
        let scan = dependencies.scanLeftovers
        let identity = app.identity
        let others = allBundleIDs.subtracting([identity.bundleID].compactMap { $0 })
        let result = await Task.detached(priority: .userInitiated) {
            scan(identity, others, { flag.isCancelled })
        }.value
        guard generation == selectionGeneration, !flag.isCancelled else { return }

        var found = result.items
        if let knownSize = app.sizeBytes, let index = found.firstIndex(where: { $0.isAppBundle }) {
            found[index].sizeBytes = knownSize            // 列表里已经算过，不再重算
        }
        items = found
        unreadableLocations = result.unreadableLocations
        checkedIDs = Set(found.filter { $0.confidence == .certain }.map(\.id))
        phase = .ready

        let sizeOf = dependencies.sizeOf
        for item in found where item.sizeBytes == nil {
            let url = item.url
            let size = await Task.detached(priority: .utility) { sizeOf(url, { flag.isCancelled }) }.value
            guard generation == selectionGeneration, !flag.isCancelled else { return }
            if let size, let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].sizeBytes = size
            }
        }
    }

    /// 三组：确定相关 / 可能相关 / 需要管理员密码。组内软件本体在最前，其余按大小从大到小。
    public var groups: [ItemGroup] {
        func ordered(_ list: [LeftoverItem]) -> [LeftoverItem] {
            list.sorted { first, second in
                if first.isAppBundle != second.isAppBundle { return first.isAppBundle }
                let a = first.sizeBytes ?? 0
                let b = second.sizeBytes ?? 0
                if a != b { return a > b }
                return first.url.path < second.url.path
            }
        }
        let certain = items.filter { !$0.needsAdmin && $0.confidence == .certain }
        let possible = items.filter { !$0.needsAdmin && $0.confidence == .possible }
        let admin = items.filter(\.needsAdmin)
        return [
            ItemGroup(id: "certain", title: "确定相关", items: ordered(certain)),
            ItemGroup(id: "possible", title: "可能相关（默认不勾选，请自己判断）", items: ordered(possible)),
            ItemGroup(id: "admin", title: "需要管理员密码", items: ordered(admin)),
        ].filter { !$0.items.isEmpty }
    }

    public func isChecked(_ item: LeftoverItem) -> Bool {
        checkedIDs.contains(item.id)
    }

    public func setChecked(_ item: LeftoverItem, _ checked: Bool) {
        guard phase == .ready else { return }
        if checked {
            checkedIDs.insert(item.id)
        } else {
            checkedIDs.remove(item.id)
        }
    }

    public func selectAll() {
        guard phase == .ready else { return }
        checkedIDs = Set(items.map(\.id))
    }

    public func selectOnlyCertain() {
        guard phase == .ready else { return }
        checkedIDs = Set(items.filter { $0.confidence == .certain }.map(\.id))
    }

    public var checkedItems: [LeftoverItem] {
        items.filter { checkedIDs.contains($0.id) }
    }

    public var checkedBytes: UInt64 {
        checkedItems.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
    }

    /// 标题行："已选 9 项，2.3 GB"
    public var summaryText: String {
        "已选 \(checkedItems.count) 项，\(SizeCalculator.format(checkedBytes))"
    }

    public var confirmationText: String {
        "将把 \(checkedItems.count) 项（\(SizeCalculator.format(checkedBytes))）移到废纸篓。可以从废纸篓恢复。"
    }

    public var canUninstall: Bool {
        phase == .ready && !checkedItems.isEmpty
    }

    public var highlightedItem: LeftoverItem? {
        items.first { $0.id == highlightedItemID }
    }

    // MARK: 执行

    /// 点了「移到废纸篓」。要移走软件本体而它正在运行 → 先请用户同意退出它。
    public func requestUninstall() {
        guard canUninstall, let app = selectedApp else { return }
        notice = nil
        if checkedItems.contains(where: \.isAppBundle), dependencies.isRunning(app.identity) {
            phase = .needsQuit
        } else {
            phase = .confirming
        }
    }

    public func quitAndContinue() async {
        guard phase == .needsQuit, let app = selectedApp else { return }
        phase = .quitting               // 立刻离开 needsQuit：提示框关掉后不会因为状态没变又弹出来
        if await dependencies.quit(app.identity) {
            phase = .confirming
        } else {
            notice = "「\(app.title)」没有退出，请手动退出它之后再试"
            phase = .ready
        }
    }

    /// 在"需要退出"或确认框里点了取消。
    public func cancelPending() {
        if phase == .needsQuit || phase == .confirming {
            phase = .ready
        }
    }

    public func confirm() async {
        guard beginRunning() else { return }
        await performTrash()
    }

    /// 给界面上的按钮用的同步入口：点下去的同一时刻状态就变了，确认框不会重复弹出。
    public func confirmTapped() {
        guard beginRunning() else { return }
        Task { await performTrash() }
    }

    public func quitTapped() {
        Task { await quitAndContinue() }
    }

    private func beginRunning() -> Bool {
        guard phase == .confirming, selectedApp != nil else { return false }
        phase = .running
        return true
    }

    private func performTrash() async {
        guard let app = selectedApp else { return }
        let toTrash = checkedItems
        let trash = dependencies.trash
        let identity = app.identity
        let report = await Task.detached(priority: .userInitiated) { trash(toTrash, identity) }.value
        guard !isTornDown else { return }
        phase = .finished(report)
    }

    /// 关掉结果页。软件本体已经移走 → 从列表里去掉它；否则重新扫描一遍，显示还剩什么。
    public func dismissResult() async {
        guard case .finished(let report) = phase, let app = selectedApp else { return }
        if report.removedAppBundle {
            apps.removeAll { $0.id == app.id }
            if let bundleID = app.identity.bundleID { allBundleIDs.remove(bundleID) }
            await select(nil)
        } else {
            await select(app)
        }
    }

    // MARK: 拖放

    /// 返回 false = 不是 .app，忽略。
    @discardableResult
    public func handleDrop(_ url: URL) async -> Bool {
        guard url.pathExtension.lowercased() == "app" else { return false }
        guard phase != .running else { return true }
        guard let dropped = dependencies.makeApp(url) else {
            notice = "读不出这个软件的信息，无法卸载"
            return true
        }
        if dependencies.isProtected(url, dropped.identity.bundleID) {
            notice = "这是系统软件，不能卸载"
            return true
        }
        let app: InstalledApp
        if let existing = apps.first(where: { $0.id == dropped.id }) {
            app = existing
        } else {
            apps.append(dropped)
            app = dropped
        }
        await select(app)
        return true
    }

    // MARK: 收尾

    /// 窗口关闭：停掉后台工作，放掉全部数据。
    public func teardown() {
        isTornDown = true
        scanFlag.cancel()
        appSizeFlag.cancel()
        selectionGeneration += 1
        apps = []
        allBundleIDs = []
        selectedApp = nil
        items = []
        checkedIDs = []
        unreadableLocations = []
        highlightedItemID = nil
        notice = nil
        phase = .idle
    }
}
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 478 tests … passed`，零警告。

- [ ] **Step 6: Commit**

```bash
git add Sources/UninstallerModule Tests/UninstallerModuleTests
git commit -m "feat(uninstaller): view model - app list, cancellable scans, checkboxes and summary, quit/confirm/run state machine, drag and drop"
```

---

### Task 6: 界面、总装、使用说明、安装与验收

**Files:**
- Create: `Sources/UninstallerModule/UninstallerViews.swift`, `Sources/UninstallerModule/UninstallerWindowController.swift`, `Sources/UninstallerModule/UninstallerModule.swift`
- Test: `Tests/UninstallerModuleTests/UninstallerModuleTests.swift`
- Modify: `Package.swift`, `Sources/MyKit/AppDelegate.swift`, `Resources/Info.plist`, `README.md`

**Interfaces:**
- Consumes: `UninstallerViewModel`、`UninstallerDependencies`（Task 5）；`AppModule`（Core）
- Produces:
  - `public enum PrivacyPane: CaseIterable { fullDiskAccess, appManagement, automation; var url: URL; func open() }`
  - `UninstallerView`（SwiftUI）、`AppIconStore`、`UninstallerWindowController`（`show(activate:)`、`close()`、`isOpen`、`window`、`model`）
  - `@MainActor public final class UninstallerModule: NSObject, AppModule`：`init(makeDependencies:)`、菜单项「卸载软件…」、无设置页

窗口只在打开时创建视图模型和图标缓存；`windowWillClose` 里调用 `model.teardown()` 并放掉一切。

- [ ] **Step 1: 写失败的测试 `Tests/UninstallerModuleTests/UninstallerModuleTests.swift`**

```swift
import AppKit
import Foundation
import Testing
@testable import UninstallerModule

@MainActor
@Suite struct UninstallerModuleTests {
    /// 完全不碰系统的依赖：空列表，什么都不做。
    private func inertDependencies() -> UninstallerDependencies {
        UninstallerDependencies(
            listApps: { InstalledAppList() },
            scanLeftovers: { _, _, _ in LeftoverScanResult() },
            sizeOf: { _, _ in 0 },
            makeApp: { _ in nil },
            isProtected: { _, _ in true },
            isRunning: { _ in false },
            quit: { _ in true },
            trash: { _, _ in TrashReport() }
        )
    }

    @Test func exposesIdentityAndASingleMenuItemAndNoSettingsPage() {
        let module = UninstallerModule(makeDependencies: inertDependencies)      // 菜单项的 target 是弱引用，模块必须活着

        #expect(module.id == "uninstaller")
        #expect(module.name == "卸载软件")
        #expect(module.menuItems.map(\.title) == ["卸载软件…"])
        #expect(module.menuItems.allSatisfy { $0.target != nil && $0.action != nil })
        #expect(module.settingsView == nil)
    }

    @Test func windowIsCreatedOnDemandAndEverythingIsReleasedOnClose() throws {
        let module = UninstallerModule(makeDependencies: inertDependencies)
        try module.start()
        #expect(!module.windowController.isOpen)                       // 平时什么都不创建

        module.windowController.show(activate: false)
        #expect(module.windowController.isOpen)
        #expect(module.windowController.model != nil)
        #expect(module.windowController.window?.title == "卸载软件")

        module.windowController.close()
        #expect(!module.windowController.isOpen)
        #expect(module.windowController.model == nil)
    }

    @Test func stoppingTheModuleClosesTheWindow() {
        let module = UninstallerModule(makeDependencies: inertDependencies)
        module.windowController.show(activate: false)

        module.stop()

        #expect(!module.windowController.isOpen)
    }

    @Test func reopeningCreatesAFreshModel() {
        let module = UninstallerModule(makeDependencies: inertDependencies)
        module.windowController.show(activate: false)
        let first = module.windowController.model
        module.windowController.close()

        module.windowController.show(activate: false)

        #expect(module.windowController.model != nil)
        #expect(module.windowController.model !== first)
        module.windowController.close()
    }

    @Test func privacyPaneLinksAreDistinctSystemSettingsURLs() {
        let urls = PrivacyPane.allCases.map(\.url.absoluteString)
        #expect(Set(urls).count == 3)
        #expect(urls.allSatisfy { $0.hasPrefix("x-apple.systempreferences:com.apple.preference.security?Privacy_") })
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'UninstallerModule' in scope`。

- [ ] **Step 3: 写 `Sources/UninstallerModule/UninstallerViews.swift`**

两个提示框的 `isPresented` 绑定只有 get 起作用（set 什么都不做）：关闭动作由各个按钮调用视图模型的同步入口完成。

```swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 系统设置里几个隐私页面的链接。
public enum PrivacyPane: CaseIterable {
    case fullDiskAccess
    case appManagement
    case automation

    public var url: URL {
        let anchor: String
        switch self {
        case .fullDiskAccess: anchor = "Privacy_AllFiles"
        case .appManagement: anchor = "Privacy_AppBundles"
        case .automation: anchor = "Privacy_Automation"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    @MainActor
    public func open() {
        NSWorkspace.shared.open(url)
    }
}

/// 图标缓存。属于卸载窗口，窗口关闭就一起释放。
@MainActor
final class AppIconStore {
    private var cache: [String: NSImage] = [:]

    func icon(forPath path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }
}

struct UninstallerView: View {
    @ObservedObject var model: UninstallerViewModel
    let icons: AppIconStore
    let home: URL

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 300)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 480)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            acceptDrop(providers)
        }
        .overlay {
            if model.phase == .running || model.phase == .quitting {
                busyOverlay
            }
        }
        .alert("软件正在运行", isPresented: binding(for: .needsQuit)) {
            Button("退出并继续") { model.quitTapped() }
            Button("取消", role: .cancel) { model.cancelPending() }
        } message: {
            Text("「\(model.selectedApp?.title ?? "")」正在运行。要卸载它，需要先退出。MyKit 只会请它正常退出，不会强制结束。")
        }
        .alert("移到废纸篓？", isPresented: binding(for: .confirming)) {
            Button("移到废纸篓", role: .destructive) { model.confirmTapped() }
            Button("取消", role: .cancel) { model.cancelPending() }
        } message: {
            Text(model.confirmationText)
        }
        .sheet(isPresented: isShowingResult) {
            if case .finished(let report) = model.phase {
                ResultView(report: report, home: home) {
                    Task { await model.dismissResult() }
                }
            }
        }
    }

    /// 提示框由状态驱动；关闭动作交给各个按钮自己处理，这里的 set 什么都不做。
    private func binding(for phase: UninstallerViewModel.Phase) -> Binding<Bool> {
        Binding(get: { model.phase == phase }, set: { _ in })
    }

    private var isShowingResult: Binding<Bool> {
        Binding(get: { if case .finished = model.phase { return true } else { return false } }, set: { _ in })
    }

    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.15)
            VStack(spacing: 10) {
                ProgressView()
                Text(model.phase == .quitting ? "正在等待软件退出…" : "正在移到废纸篓…")
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: 左侧：软件列表

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                TextField("搜索软件…", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                Picker("排序", selection: $model.sortOrder) {
                    ForEach(AppListing.SortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(10)
            Divider()
            if model.isLoadingApps {
                Spacer()
                ProgressView("正在列出已安装的软件…")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(model.visibleApps) { app in
                            AppRow(app: app, icon: icons.icon(forPath: app.identity.url.path),
                                   isSelected: app.id == model.selectedApp?.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task { await model.select(app) }
                                }
                        }
                    }
                    .padding(6)
                }
            }
            Divider()
            Text("也可以把 .app 从访达拖到这个窗口里")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    // MARK: 右侧：清单

    @ViewBuilder
    private var detail: some View {
        if let app = model.selectedApp {
            VStack(spacing: 0) {
                header(app)
                Divider()
                if model.phase == .scanning {
                    Spacer()
                    ProgressView("正在查找相关文件…")
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(model.groups) { group in
                                Text(group.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 10)
                                    .padding(.horizontal, 6)
                                ForEach(group.items) { item in
                                    ItemRow(
                                        item: item,
                                        icon: icons.icon(forPath: item.url.path),
                                        location: PathDisplay.location(of: item.url, home: home),
                                        isChecked: Binding(
                                            get: { model.isChecked(item) },
                                            set: { model.setChecked(item, $0) }),
                                        isHighlighted: model.highlightedItemID == item.id
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.highlightedItemID = item.id }
                                }
                            }
                        }
                        .padding(10)
                    }
                }
                Divider()
                footer
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "trash.square")
                    .font(.system(size: 44))
                    .foregroundStyle(.tertiary)
                Text("从左边选一个软件，或者把 .app 拖到这里")
                    .foregroundStyle(.secondary)
                Text("所有内容只会移到废纸篓，可以随时放回原处")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                if let notice = model.notice {
                    Text(notice)
                        .foregroundStyle(.orange)
                        .padding(.top, 6)
                }
            }
        }
    }

    private func header(_ app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: icons.icon(forPath: app.identity.url.path))
                    .resizable()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.identity.version.map { "\(app.title)  \($0)" } ?? app.title)
                        .font(.headline)
                    Text(app.identity.bundleID ?? "（没有标识符，只能按名称查找）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.summaryText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("全选") { model.selectAll() }
                Button("只选确定相关") { model.selectOnlyCertain() }
                Spacer()
            }
            .disabled(model.phase != .ready)
        }
        .padding(12)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice = model.notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if !model.unreadableLocations.isEmpty {
                HStack {
                    Text("有 \(model.unreadableLocations.count) 个位置无权读取。授予 MyKit「完全磁盘访问权限」后可以找得更全（不授予也能用）。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("打开系统设置") { PrivacyPane.fullDiskAccess.open() }
                        .controlSize(.small)
                }
            }
            HStack {
                Spacer()
                Button("在访达中显示") {
                    if let item = model.highlightedItem {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }
                }
                .disabled(model.highlightedItem == nil)
                Button("移到废纸篓") { model.requestUninstall() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canUninstall)
            }
        }
        .padding(12)
    }

    // MARK: 拖放

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let identifier = UTType.fileURL.identifier
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(identifier) }) else { return false }
        let model = self.model
        provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
            var dropped: URL?
            if let data = item as? Data {
                dropped = URL(dataRepresentation: data, relativeTo: nil)
            } else if let url = item as? URL {
                dropped = url
            }
            guard let dropped else { return }
            Task { @MainActor in
                await model.handleDrop(dropped)
            }
        }
        return true
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let icon: NSImage
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 24, height: 24)
            Text(app.title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(app.sizeBytes.map(SizeCalculator.format) ?? "计算中…")
                .font(.caption.monospacedDigit())
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accentColor : Color.clear))
    }
}

private struct ItemRow: View {
    let item: LeftoverItem
    let icon: NSImage
    let location: String
    @Binding var isChecked: Bool
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $isChecked)
                .toggleStyle(.checkbox)
                .labelsHidden()
            Image(nsImage: icon)
                .resizable()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(item.category) · \(location)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Text(item.sizeBytes.map(SizeCalculator.format) ?? "…")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(isHighlighted ? Color.accentColor.opacity(0.18) : Color.clear))
        .help(item.url.path)
    }
}

private struct ResultView: View {
    let report: TrashReport
    let home: URL
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(report.summary)
                .font(.headline)
            if !report.succeeded.isEmpty {
                Text("它们现在在废纸篓里。想恢复：打开废纸篓，右键点那一项，选「放回原处」。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if report.touchedBackgroundServices {
                Text("其中的后台服务在重启电脑后才会完全停止。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !report.failed.isEmpty {
                Text("没有移走的项：")
                    .font(.subheadline.weight(.semibold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(report.failed) { failure in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(PathDisplay.abbreviated(failure.item.url, home: home))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(failure.reason)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
            if report.appManagementBlocked {
                HStack {
                    Text("系统拦住了 MyKit 移动其他软件。请在「隐私与安全性 → App 管理」里打开 MyKit，然后再试一次。")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("打开「App 管理」") { PrivacyPane.appManagement.open() }
                }
            }
            if report.automationDenied {
                HStack {
                    Text("需要管理员权限的项要请访达来移走。请在「隐私与安全性 → 自动化」里允许 MyKit 控制访达，然后再试一次。")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("打开「自动化」") { PrivacyPane.automation.open() }
                }
            }
            HStack {
                Spacer()
                Button("好", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
```

- [ ] **Step 4: 写 `Sources/UninstallerModule/UninstallerWindowController.swift`**

```swift
import AppKit
import SwiftUI

/// 卸载窗口。打开时才创建视图模型和图标缓存；关闭时全部释放，什么都不留在内存里。
@MainActor
final class UninstallerWindowController: NSObject, NSWindowDelegate {
    private let makeDependencies: () -> UninstallerDependencies
    private(set) var window: NSWindow?
    private(set) var model: UninstallerViewModel?

    init(makeDependencies: @escaping () -> UninstallerDependencies) {
        self.makeDependencies = makeDependencies
    }

    var isOpen: Bool { window != nil }

    /// activate = false 只在测试里用（测试进程里没有正在运行的 NSApplication）。
    func show(activate: Bool = true) {
        if window == nil {
            let model = UninstallerViewModel(dependencies: makeDependencies())
            let view = UninstallerView(
                model: model, icons: AppIconStore(), home: FileManager.default.homeDirectoryForCurrentUser)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "卸载软件"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 760, height: 480)
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.delegate = self
            self.window = window
            self.model = model
            model.start()
        }
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        model?.teardown()
        model = nil
        let closing = window
        window = nil
        closing?.delegate = nil
        // 等系统把关闭流程走完，再放掉界面（连同图标缓存）
        DispatchQueue.main.async {
            closing?.contentView = nil
        }
    }
}
```

- [ ] **Step 5: 写 `Sources/UninstallerModule/UninstallerModule.swift`**

```swift
import AppKit
import Core
import SwiftUI

/// 卸载器：右上角菜单里的「卸载软件…」。平时零开销，窗口关闭后不留任何东西。
@MainActor
public final class UninstallerModule: NSObject, AppModule {
    public let id = "uninstaller"
    public let name = "卸载软件"

    let windowController: UninstallerWindowController

    /// makeDependencies 只在测试里替换。
    public init(makeDependencies: @escaping () -> UninstallerDependencies = { .live() }) {
        self.windowController = UninstallerWindowController(makeDependencies: makeDependencies)
        super.init()
    }

    public func start() throws {}

    public func stop() {
        windowController.close()
    }

    private lazy var openMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "卸载软件…", action: #selector(openFromMenu), keyEquivalent: "")
        item.target = self
        return item
    }()

    public var menuItems: [NSMenuItem] {
        [openMenuItem]
    }

    @objc private func openFromMenu() {
        windowController.show()
    }
}
```

- [ ] **Step 6: 更新 `Package.swift`**

完整内容（`MyKit` 现在依赖 `UninstallerModule`）：

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyKit",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Core"),
        .target(
            name: "ClipboardModule",
            dependencies: ["Core"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "ScreenshotModule", dependencies: ["Core"]),
        .target(name: "SystemMonitorModule", dependencies: ["Core"]),
        .target(name: "UninstallerModule", dependencies: ["Core"]),
        .executableTarget(
            name: "MyKit",
            dependencies: ["Core", "ClipboardModule", "ScreenshotModule", "SystemMonitorModule", "UninstallerModule"]
        ),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "ClipboardModuleTests", dependencies: ["ClipboardModule"]),
        .testTarget(name: "ScreenshotModuleTests", dependencies: ["ScreenshotModule"]),
        .testTarget(name: "SystemMonitorModuleTests", dependencies: ["SystemMonitorModule"]),
        .testTarget(name: "UninstallerModuleTests", dependencies: ["UninstallerModule"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 7: 整体替换 `Sources/MyKit/AppDelegate.swift`**

相对现有文件只有三处变化：`import UninstallerModule`、新增属性 `uninstaller`、在截图模块之后注册卸载器。其余（系统监控最先注册、快捷键接线、授权引导、图标状态）原样保留：

```swift
import AppKit
import ClipboardModule
import Core
import ScreenshotModule
import SystemMonitorModule
import UninstallerModule
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.imiros.mykit", category: "app")
    private let registry = ModuleRegistry()
    private let eventTap = GlobalKeyTap()
    private let hotkeys = HotkeySettings()
    private var hotkeyObservers: [NSObjectProtocol] = []
    private let accessibilityWatcher = AccessibilityWatcher()
    private let onboarding = OnboardingWindowController()
    private var clipboard: ClipboardModule?
    private var screenshot: ScreenshotModule?
    private var monitor: SystemMonitorModule?
    private var uninstaller: UninstallerModule?
    private var statusBar: StatusBarController?
    private var settingsWindow: SettingsWindowController?
    private var eventTapFailed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 系统监控最先注册：它的菜单项（CPU / 内存和排行榜）因此排在菜单最上面
        let monitor = SystemMonitorModule()
        monitor.onMenuBarTitleChange = { [weak self] title in
            self?.statusBar?.setTitle(title)
        }
        registry.register(monitor)
        self.monitor = monitor

        do {
            let clipboard = try ClipboardModule(databaseURL: ClipboardModule.defaultDatabaseURL)
            clipboard.onPausedChange = { [weak self] _ in self?.refreshIcon() }
            registry.register(clipboard)
            self.clipboard = clipboard
        } catch {
            log.error("剪切板模块初始化失败: \(String(describing: error), privacy: .public)")
        }

        let screenshot = ScreenshotModule()
        registry.register(screenshot)
        self.screenshot = screenshot

        // 卸载器：只有一个菜单项，窗口打开时才工作，平时零开销
        let uninstaller = UninstallerModule()
        registry.register(uninstaller)
        self.uninstaller = uninstaller

        registry.startAll()
        for failure in registry.failures {
            log.error("模块 \(failure.id, privacy: .public) 启动失败: \(String(describing: failure.error), privacy: .public)")
        }

        // 偏好设置里的顺序：剪切板、截图在前，系统监控放最后
        let settingsModules = registry.modules.filter { $0 !== monitor } + [monitor]
        let settingsWindow = SettingsWindowController(modules: settingsModules)
        self.settingsWindow = settingsWindow
        statusBar = StatusBarController(
            moduleMenuItems: registry.menuItemsWithSeparators,
            onOpenSettings: { settingsWindow.show() },
            onMenuWillOpen: { [weak self] in self?.registry.menuWillOpen() },
            onMenuDidClose: { [weak self] in self?.registry.menuDidClose() }
        )
        // 模块启动时状态栏还没创建，第一次的标题在这里补上
        statusBar?.setTitle(monitor.currentMenuBarTitle)

        eventTap.onDoubleTap = { [weak self] in
            self?.clipboard?.togglePanel()
        }
        applyHotkeys()
        observeHotkeySettings()
        accessibilityWatcher.onChange = { [weak self] trusted in
            self?.accessibilityChanged(trusted)
        }
        accessibilityWatcher.start()
        accessibilityChanged(accessibilityWatcher.isTrusted)

        log.info("MyKit 已启动，辅助功能授权=\(self.accessibilityWatcher.isTrusted), 剪切板需用户批准=\(Permissions.pasteboardNeedsUserApproval)")

        if clipboard?.recoveredFromCorruption == true {
            showDatabaseRecoveredAlert()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap.stop()
        accessibilityWatcher.stop()
        registry.stopAll()
    }

    /// 按当前设置（重新）注册快捷键。用户在偏好设置里改完立即调用，无需重启。
    private func applyHotkeys() {
        eventTap.unregisterAll()
        eventTap.doubleTapModifier = hotkeys.clipboardDoubleTap
        eventTap.register(hotkeys.screenshotCombo) { [weak self] in
            self?.screenshot?.startCapture()
        }
    }

    private func observeHotkeySettings() {
        let center = NotificationCenter.default
        hotkeyObservers = [
            center.addObserver(forName: HotkeySettings.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyHotkeys() }
            },
            // 设置页录制新快捷键期间暂停全局监听，否则现有快捷键会被吞掉、录不进去
            center.addObserver(forName: HotkeySettings.recordingDidBeginNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.eventTap.isSuspended = true }
            },
            center.addObserver(forName: HotkeySettings.recordingDidEndNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.eventTap.isSuspended = false }
            },
        ]
    }

    /// 授权状态变化（含启动时的首次检查）：有权限就开始监听双击 Option，没有就弹引导。
    private func accessibilityChanged(_ trusted: Bool) {
        if trusted {
            eventTapFailed = !eventTap.start()
            onboarding.close()
        } else {
            eventTap.stop()
            eventTapFailed = false
            onboarding.show()
        }
        refreshIcon()
    }

    private func refreshIcon() {
        if !accessibilityWatcher.isTrusted || eventTapFailed {
            statusBar?.setIcon(.warning)
        } else if clipboard?.isPaused == true {
            statusBar?.setIcon(.paused)
        } else {
            statusBar?.setIcon(.normal)
        }
    }

    private func showDatabaseRecoveredAlert() {
        let alert = NSAlert()
        alert.messageText = "剪切板历史已重建"
        alert.informativeText = "原来的历史数据库已损坏，MyKit 已将它备份并新建了一个空的历史。备份文件在 ~/Library/Application Support/MyKit/ 里。"
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
```

- [ ] **Step 8: 整体替换 `Resources/Info.plist`**

新增 `NSAppleEventsUsageDescription`（第一次请访达帮忙时，系统会把这句话显示在授权提示里）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.imiros.mykit</string>
    <key>CFBundleName</key>
    <string>MyKit</string>
    <key>CFBundleDisplayName</key>
    <string>MyKit</string>
    <key>CFBundleExecutable</key>
    <string>MyKit</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>卸载软件时，需要管理员权限的文件要请访达来移到废纸篓。</string>
</dict>
</plist>
```

- [ ] **Step 9: 运行测试并做 release 构建**

Run: `scripts/test.sh && swift build -c release --build-system native`
Expected: `✔ Test run with 483 tests … passed`，零警告；`Build complete!`。

- [ ] **Step 10: 整体替换 README.md**

完整内容：

````markdown
# MyKit

Mac 菜单栏小工具箱。目前的功能：

- **剪切板历史** —— 双击 Option 呼出，保留最近 7 天复制过的文字，可搜索，回车直接粘贴；每条记录前面的图标表示它是从哪个 App 复制的。
- **截图** —— 按 `⇧⌘A`，框选或点选窗口，然后复制 / 保存 / 识别文字 / 贴在屏幕上。
- **系统监控** —— 右上角图标旁边一直显示 CPU 和内存占用；点开菜单能看到最占资源的 5 个软件。
- **卸载软件** —— 选一个软件，连同它散落在各处的残留文件（包括隐藏文件）一起移到废纸篓；移走之前先让你过目。

## 安装

在"终端"里进入本目录，依次运行：

```bash
scripts/create-dev-cert.sh   # 只需要运行一次
scripts/build-app.sh
scripts/install.sh
```

完成后屏幕右上角会出现 MyKit 图标（三层叠起来的方块），旁边是 `CPU 12%  内存 63%` 这样的一行数字。

## 第一次使用：授权

MyKit 需要两项系统授权，都只需要做一次。

**辅助功能**（双击 Option、`⇧⌘A`、自动粘贴都靠它）—— 第一次启动会弹出引导窗口：

1. 点「打开系统设置」
2. 在「辅助功能」列表里找到 MyKit，打开右边的开关
3. 引导窗口会自动关闭，授权完成

**屏幕录制**（截图靠它）—— 第一次按 `⇧⌘A` 时会弹出引导窗口：

1. 点「打开系统设置」
2. 在「录屏与系统录音」列表里找到 MyKit，打开右边的开关
3. 回到引导窗口，点「重新启动 MyKit」（这项权限要重启后才生效）

如果右上角图标变成 ⚠️ 三角形，说明辅助功能授权丢失了，重新打开开关即可。
以后系统可能会定期询问"是否继续允许 MyKit 录制屏幕"，选「继续允许」。
第一次把截图保存到桌面时，系统会问"是否允许 MyKit 访问桌面文件夹"，选「允许」。

## 剪切板怎么用

| 操作 | 效果 |
|---|---|
| 快速按两下 Option | 打开 / 关闭剪切板面板 |
| 直接打字 | 搜索 |
| ↑ ↓ | 选择 |
| 回车 | 粘贴到刚才正在用的 App |
| ⌘1 – ⌘9 | 直接粘贴第 1–9 条 |
| ⌘⌫ | 删除选中的记录 |
| Esc 或点击面板外 | 关闭面板 |

## 截图怎么用

按 `⇧⌘A`（或点右上角图标 →「截图」），屏幕会定格并变暗：

- 把鼠标移到某个窗口上，它会变亮，**单击**就选中整个窗口；
- 或者**按住拖动**，框出任意一块区域；
- 选好后可以拖边上的小方块改大小、在选区里拖动改位置。

选区旁边会出现工具条：

| 按钮 | 键盘 | 效果 |
|---|---|---|
| 复制 | 回车 / `⌘C` / 双击选区 | 图片进剪切板，可以直接粘贴到微信、文档里 |
| 保存 | `⌘S` | 存成 PNG 文件（默认在桌面，可在偏好设置里改） |
| 识别文字 | `⌘R` | 打了马赛克的地方不会被识别，箭头、方框等其他标注不影响识别。**截图画面不关闭**，识别结果出现在选区旁边，方便对照原图；文字可以改、可以只选一部分，全文同时已自动复制。点「完成」或按 `Esc` 结束截图；点一下定格画面则收起结果、继续截图（可以调整选区再识别，或接着复制 / 保存 / 贴图） |
| 贴图 | `⌘T` | 截图原地浮在屏幕上，方便对照着看 |
| 取消 | Esc / 右键 | 逐级取消：正在打字 → 完成输入；选着标注工具 → 取消工具；有选区 → 清除选区（标注一起清掉）重新选；再按一次退出截图 |

### 标注

选好区域后，工具条左边有一排标注工具（鼠标停在按钮上会显示名字）。点一下选中，再点一次取消；选中后下面会多出一行，可以选 6 种颜色和 细 / 中 / 粗 三档，你的选择会被记住。

| 工具 | 怎么用 |
|---|---|
| 方框 / 椭圆 | 按住拖动。按住 `Shift` 画正方形 / 正圆 |
| 箭头 / 直线 | 从起点拖到终点。按住 `Shift` 吸附到水平、垂直或 45° |
| 画笔 | 随手涂画 |
| 荧光笔 | 半透明的粗线，给文字做高亮。按住 `Shift` 画直线 |
| 文字 | 点一下出现输入框，直接打字（支持中文输入法，回车换行），点别处或按 `Esc` 完成 |
| 马赛克 | 拖出一个矩形，里面变成方块，用来遮手机号、密码等 |
| 序号 | 每点一下放一个 ①②③…，自动递增 |

- 画错了按 `⌘Z` 撤销，`⇧⌘Z` 重做（工具条上也有按钮）。画好的标注不能再选中移动，撤销重画即可。
- 标注只能画在选区里面。
- 选了工具或已经有标注时，选区不能再移动 / 改大小；想调整选区，先把标注全部撤销并取消选中工具。
- 复制 / 保存 / 贴图得到的图片都带标注。

**翻译成中文**：识别结果面板上有一个「翻译成中文」勾选框。勾上后，面板下半部分显示中文译文（旁边有「复制译文」），并且**以后每次识别完都会自动翻译**，直到你取消勾选。只翻译英文；识别内容里没有英文时会提示"没有可翻译的英文"。翻译用的是 macOS 自带的翻译功能：离线、免费、不用注册。翻译时截图画面**不会关闭**。**第一次使用**时系统会提示下载英译中语言包（只需一次）：这时截图画面会临时让出窗口层级（画面还在，菜单栏会露出来），好让系统的下载提示显示在上面；点「下载」，完成后重新勾选一次「翻译成中文」即可。如果没有看到下载提示，可以手动下载：系统设置 → 通用 → 语言与地区 → 翻译语言，下载「英语」和「简体中文」。需要 macOS 15 或更新的系统。

**贴图**：拖动可以移动；滚轮（或触控板双指上下滑动）缩放，也可以用触控板**双指捏合**放大缩小；双击关闭；右键有 复制 / 保存 / 识别文字 / 关闭 / 关闭全部贴图。右上角菜单里也有「关闭所有贴图」。

## 系统监控怎么用

- **菜单栏**：MyKit 图标右边一直显示 `CPU 12%  内存 63%`，默认每 2 秒刷新一次。哪一项到了 85% 或更高，那个数字会变成红色。刚启动的头两秒 CPU 显示 `--`（需要两次读数才能算出占用），属正常。
- **点开菜单**：最上面是 CPU 和内存的总数（CPU 还分"用户 / 系统"，内存显示"已用 / 总量"），下面各列出最占资源的 5 个软件，带图标。内存榜一打开就有；CPU 榜要统计约 1 秒，之前显示"正在统计…"。菜单开着的时候排行会持续刷新，关上就停止统计。
- 同一个软件的所有辅助进程会合并成一项（比如 Chrome 的几十个 Helper 都算在"Google Chrome"头上）。
- 单个软件的 CPU 百分比和系统的"活动监视器"算法一致：占满一个核心是 100%，同时用多个核心可以超过 100%。所以它可能比菜单栏上的总 CPU 数字大，这是正常的（总数是占全部核心的比例）。
- 系统自己的后台进程（WindowServer、kernel_task 等）普通软件读不到，不会出现在排行里；你自己打开的软件都在。
- 「打开活动监视器…」会启动系统自带的那个工具。MyKit 不提供"结束进程"这类有风险的操作。
- **设置**：「偏好设置…」→「系统监控」里可以关掉菜单栏上的数字（关掉后点开菜单仍然能看），也可以把刷新间隔改成 1 秒 / 2 秒 / 5 秒，改完立即生效。

系统监控不需要任何授权，不联网，不调用外部命令，数据直接从 macOS 内核读取。平时每次刷新只读两个计数器；排行榜只在菜单打开时才统计。

## 卸载软件怎么用

点右上角图标 →「卸载软件…」。

1. **选软件**：左边是已安装软件的列表，可以搜索，也可以按名称 / 大小排序（大小在后台慢慢算，算好一个显示一个）。也可以直接把一个 `.app` 从访达拖进窗口。系统自带的软件（Safari、邮件……）和 MyKit 自己不在列表里，拖进来也会被拒绝。
2. **看清单**：右边列出要移走的东西，分三组：
   - **确定相关**（默认勾选）：软件本体，以及名字里带着这个软件独有标识的文件 —— 应用数据、缓存、偏好设置、容器、日志、崩溃报告、登录启动项、系统临时缓存……
   - **可能相关**（默认**不**勾选）：只是同名或名字沾边的东西，比如主目录下的隐藏文件夹 `~/.docker`、以厂商命名的文件夹。它们也可能属于别的软件，请自己判断后再勾。
   - **需要管理员密码**：位于系统级目录的项（后台服务、特权帮助程序、安装记录等）。
   - 「全选」一键勾上所有项（想卸得最彻底时用）；「只选确定相关」恢复默认。点一行再点「在访达中显示」可以看看它到底是什么。
3. **移到废纸篓**：点按钮后会先弹出确认框。如果软件正在运行，会先问你要不要退出它（只会正常退出，不会强制结束）。
4. **看结果**：移走了多少项、释放了多少空间；没移走的会逐条写明原因。

**安全方面**：

- 所有内容**只是移到废纸篓**，MyKit 里没有任何永久删除。后悔了：打开废纸篓，右键点那一项，选「放回原处」。清空废纸篓由你自己决定。
- 每一条在真正移走之前都会再检查一遍，只有"软件本体"和"那些固定位置下的直接子项"才会被移动；`~/Library/Preferences` 这类目录本身、系统目录、`.ssh` 之类的敏感文件永远不会被碰。
- 需要管理员权限的项由**访达**来移（系统自己弹密码框），MyKit 不接触你的密码。移走后台服务之后，要重启电脑它才会完全停止。

**可能遇到的系统提示**（都只需要处理一次）：

- 「MyKit 想要管理其他 App」→ 允许。如果当时点了不允许：系统设置 → 隐私与安全性 → App 管理，打开 MyKit。
- 「MyKit 想要控制访达」→ 允许（只在遇到需要管理员权限的项时出现）。如果点了不允许：隐私与安全性 → 自动化。
- 窗口底部提示"有 N 个位置无权读取"→ 不处理也能用；想找得更全，就在 隐私与安全性 → 完全磁盘访问权限 里打开 MyKit。

卸载窗口关掉之后不会留下任何后台任务。这一版不做：自动发现你刚拖进废纸篓的软件、清空废纸篓、浏览器插件和系统扩展的专门卸载、一次卸载多个软件。

## 修改快捷键

点右上角图标 →「偏好设置…」，改完**立即生效**，不用重启：

- **截图快捷键**：在「截图」一栏点一下显示着 `⇧⌘A` 的按钮 → 它会变成"请按下新的快捷键…" → 按下你想要的组合键即可（按 `Esc` 取消；15 秒不按自动取消）。普通按键必须带 `⌘`、`⌃` 或 `⌥` 之一；`F1`–`F12` 可以单独用。复制 / 粘贴 / 退出这类系统常用键不允许设置。旁边的「恢复默认」会改回 `⇧⌘A`。
- **剪切板呼出方式**：在「剪切板历史」一栏的「呼出方式」里选 双击 Option / 双击 Control / 双击 Command。

**快捷键说明：** `⇧⌘A` 在个别 App 里原本有别的用途（访达里是打开「应用程序」文件夹，Chrome 里是搜索标签页）；MyKit 运行时这个键优先用于截图。钉钉的截图默认也是 `⇧⌘A`，如果按下后出来的是钉钉的截图，到钉钉「设置 → 快捷键」里把截图快捷键关掉或改成别的键。

## 退出

**左键或右键**点击右上角的 MyKit 图标 →「退出 MyKit」。

同一个菜单里还有：CPU / 内存和排行榜、打开活动监视器、打开剪切板、暂停记录、截图、关闭所有贴图、卸载软件、偏好设置（保留天数、开机自启、清空历史、截图保存位置、系统监控的显示与刷新间隔）。

## 数据在哪里

剪切板历史：`~/Library/Application Support/MyKit/clipboard.sqlite`，只保存在本机，不联网。从密码管理器复制的密码不会被记录。
截图：只有你点「保存」时才会写文件；文字识别在本机完成，不联网。
系统监控：只在内存里保留最近一次的读数，不写任何文件。
卸载软件：不保存任何记录；被移走的东西都在系统的废纸篓里。

## 更新

改了代码之后重新运行 `scripts/build-app.sh && scripts/install.sh`，不需要重新授权。

## 开发

```bash
scripts/test.sh                                   # 跑全部单元测试
scripts/test.sh --filter SelectionModelTests      # 只跑一组
```

设计文档：`docs/superpowers/specs/`；实现计划：`docs/superpowers/plans/`
````

- [ ] **Step 11: 构建、安装、确认启动正常**

```bash
scripts/build-app.sh && scripts/install.sh
/usr/bin/plutil -p /Applications/MyKit.app/Contents/Info.plist | grep NSAppleEventsUsageDescription
perl -e 'select(undef,undef,undef,3)'          # 等 3 秒（这个环境里前台 sleep 可能被拦）
/usr/bin/log show --last 1m --predicate 'process == "MyKit" AND subsystem == "com.imiros.mykit"' --info | grep -E "已启动|失败"
```

Expected: `designated => identifier "com.imiros.mykit" …` 与 `完成：build/MyKit.app`；`plutil` 那一行能看到新加的说明文字；日志里有 `MyKit 已启动`，没有"失败"。**到此为止不要打开卸载窗口做任何真实的卸载** —— 那是下一步由用户本人做的事。

- [ ] **Step 12: 手动验收（需要用户本人操作；逐条确认，任何一条不符合就修复后重测）**

前 8 条**只是看**，不会移动任何东西；从第 9 条开始才会真的把东西移到废纸篓，并且只针对一个专门为测试安装的小软件。

**只看，不动任何东西**

1. 点右上角 MyKit 图标。→ 菜单里多了「卸载软件…」（在「截图」「关闭所有贴图」下面）。
2. 点「卸载软件…」。→ 出现"卸载软件"窗口：左边先显示"正在列出已安装的软件…"，随后列出软件（带图标）；右边提示"从左边选一个软件，或者把 .app 拖到这里"。
3. 等一会儿。→ 每个软件右边的"计算中…"陆续变成大小；期间窗口不卡。点「大小」→ 大的排前面，还没算好的排最后；点「名称」→ 回到按名字排。
4. 在搜索框里输入某个软件名字的一部分（中文、英文都试一下）。→ 列表只剩匹配的软件；清空后恢复。
5. 检查列表。→ **没有** Safari、邮件、备忘录这些系统自带的软件，也**没有** MyKit 自己。
6. 点一个你熟悉的软件（**不要**点「移到废纸篓」）。→ 右边先显示"正在查找相关文件…"，然后列出清单：第一条是软件本体；「确定相关」里的项默认打勾；如果有「可能相关」，默认不打勾，其中以 `.` 开头的隐藏文件夹（比如 `.docker`）就在这一组；位于 `/Library/…` 的项在「需要管理员密码」一组。右上角显示"已选 N 项，X"。
7. 把鼠标停在某一行上。→ 显示完整路径。点一下那一行再点「在访达中显示」。→ 访达打开并选中了那个文件 / 文件夹。点「全选」→ 全部打勾，右上角的数字变大；点「只选确定相关」→ 恢复默认。
8. 从访达的"应用程序"里把 Safari 拖进窗口。→ 提示"这是系统软件，不能卸载"，什么都没选中。把一个文稿（比如 PDF）拖进去 → 没有任何反应。关闭窗口。

**真的卸载一个测试用的小软件**

9. 先准备：从 App Store 以外的地方装一个**不重要的免费小软件**（比如随便一个小工具），打开用一下再退出（让它留下一些数据）。重新打开「卸载软件…」，选中它。→ 清单里能看到它的本体和若干残留。
10. 先**打开**这个小软件，再回到卸载窗口点「移到废纸篓」。→ 提示"软件正在运行"；点「退出并继续」→ 它正常退出（未保存的内容它自己会问），然后出现确认框"将把 N 项（X）移到废纸篓。可以从废纸篓恢复。"；先点「取消」→ 什么都没发生。
11. 再点「移到废纸篓」→「移到废纸篓」。第一次系统可能会问"MyKit 想要管理其他 App"→ 点允许。→ 出现结果页"已移到废纸篓 N 项，释放 X"；点「好」后，那个软件从左边的列表里消失。
12. 打开废纸篓。→ 能看到刚才那个软件和它的残留文件。右键点其中一项 →「放回原处」→ 它回到了原来的位置。（验证完可以把它们再拖回废纸篓。）
13. 如果第 11 步里点了"不允许"：→ 结果页写着软件本体没有移走，并有「打开「App 管理」」按钮，点它能打开系统设置的对应页面；在那里打开 MyKit 后重试即可成功。
14. 找一个从 **App Store** 安装的、不重要的软件（没有就跳过这一条）。选中它 →「移到废纸篓」。→ 系统可能先问"MyKit 想要控制访达"（允许），然后访达弹出**系统自己的**管理员密码框；输入后软件被移到废纸篓。在密码框点取消 → 结果页写明"需要管理员密码，你取消了输入"，软件原封不动。
15. 选一个装过后台服务的软件（没有就跳过）。→ 「需要管理员密码」一组里有"后台服务"类别的项；移走之后结果页多一句"其中的后台服务在重启电脑后才会完全停止"。
16. 窗口底部如果出现"有 N 个位置无权读取…"。→ 属正常；点「打开系统设置」能打开"完全磁盘访问权限"页面。授权与否都不影响使用，授权后能找到的"容器数据"会更多。

**其他**

17. 只清残留、不删软件：选中一个软件，取消勾选第一条（软件本体），只留下缓存之类 →「移到废纸篓」。→ 即使软件正在运行也不会要求退出；完成后软件还在列表里，清单被重新扫描了一遍。
18. 把"下载"文件夹里的一个 `.app`（不在"应用程序"里）拖进窗口。→ 它被加进列表并选中，可以像其他软件一样卸载。
19. 扫描到一半（刚点了一个大软件）马上点另一个软件。→ 右边显示的是后点的那个软件的清单，不会串。
20. 打开"活动监视器"找到 MyKit，记下内存；打开卸载窗口、等大小算完、关闭窗口，过几秒再看。→ 内存回落到接近打开之前；CPU 回到接近 0（窗口关闭后没有任何后台工作）。
21. 回归：双击 Option 的剪切板、`⇧⌘A` 截图（含标注、识别文字）、菜单栏上的 CPU / 内存数字和排行榜、偏好设置，都和以前一样。

- [ ] **Step 13: Commit**

```bash
git add Package.swift Sources Tests Resources/Info.plist README.md
git commit -m "feat: uninstaller module - app list with drag and drop, thorough leftover scan, move to Trash only, Finder for admin items, README"
```
