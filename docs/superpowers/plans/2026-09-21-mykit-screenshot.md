# MyKit 截图模块（第一期）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 MyKit 增加类似 Snipaste 的截图：按 `⌃⌘A` 定格屏幕，框选或点选窗口，然后复制 / 保存 PNG / 识别文字（OCR）/ 贴在屏幕上。

**Architecture:** 新增 SwiftPM Target `ScreenshotModule`（依赖 `Core`，实现 `AppModule`），不改动剪切板模块的对外行为。`Core` 的键盘监听从"只认双击 Option"扩展为也认已注册的组合键并吞掉它（`ModifierEventTap` 改名 `GlobalKeyTap`）。截图流程：ScreenCaptureKit 把每块屏各定格成一张图 → 每块屏一个不激活 App 的全屏 `NSPanel` 遮罩 → 纯状态机 `SelectionModel` 处理悬停 / 框选 / 移动 / 缩放 → 裁剪 → 执行操作。几何、选区、裁剪、文件名、保存回退、OCR 排序、贴图缩放都是可单元测试的纯逻辑；窗口和鼠标键盘部分用手动验收清单覆盖。

**Tech Stack:** Swift 6.4（语言模式 5）、AppKit + SwiftUI、ScreenCaptureKit（`SCScreenshotManager`）、Vision（`VNRecognizeTextRequest`）、Swift Testing、bash 脚本。无第三方依赖。

**Spec:** `docs/superpowers/specs/2026-09-21-mykit-screenshot-design.md`

## Global Constraints

- 运行环境：macOS 27，只有 Command Line Tools，**没有 Xcode**。不要使用 `xcodebuild`、`.xcodeproj`、XCTest。
- 构建必须带 `--build-system native`（默认的 swiftbuild 在仅 CLT 环境下报 "Could not initialize build system"）。会出现一条 deprecated 警告，忽略即可。
- 跑测试**只用** `scripts/test.sh`（它补上了 Swift Testing 的框架 / 宏插件 / rpath 参数）；直接 `swift test` 会报 `no such module 'Testing'`。
- 测试框架：Swift Testing（`import Testing`、`@Test`、`#expect`、`#require`）。
- **`#expect` 里不要写字面量算式**（如 `#expect(x == 1600 - 16)`）：宏展开后类型推断出错，明明相等也会判为失败。先算好写成单个字面量，或先赋给 `let`。同理，`try` / `await` 的结果先赋给 `let` 再 `#expect`。
- `Package.swift`：`// swift-tools-version: 6.0`，`platforms: [.macOS(.v14)]`，`swiftLanguageModes: [.v5]`。
- **不要写 `@State`**：macOS 27 SDK 里它是宏（`SwiftUIMacros.StateMacro`），宏插件只随 Xcode 提供，CLT 下编译报 `plugin for module 'SwiftUIMacros' not found`。一律用 `Core` 里的别名 `@ViewState`，或把状态放进 `ObservableObject`。`@FocusState`、`@AppStorage`、`@ObservedObject`、`@Published` 不受影响。同理不要用 `#Preview`、`@Entry`、`@Animatable`。
- 最低系统 macOS 14（`SCScreenshotManager` 需要 14）；高于 14 的 API 必须包在 `#available` 里。
- 不引入任何第三方依赖。
- bundle id：`com.imiros.mykit`；软件名：`MyKit`；日志 subsystem：`com.imiros.mykit`。
- 剪切板标记类型：自己粘贴时写入的 `com.imiros.mykit.own-write`（已有）；MyKit 自己产生的文字 `com.imiros.mykit.origin`（本计划新增）。
- 签名：证书名 `MyKit Dev`，专用钥匙串 `~/Library/Keychains/mykit-dev.keychain-db`，钥匙串密码 `mykit-dev`。**不要**用 ad-hoc 签名（`-s -`），否则每次重编译授权都会失效。证书已存在，不需要再运行 `scripts/create-dev-cert.sh`。
- 事件监听用 `CGEvent.tapCreate(... options: .defaultTap ...)`（只需"辅助功能"一项授权，且只有它能吞掉事件）。未匹配的事件必须原样返回。
- 所有面向用户的文案用简体中文。
- 终端是 zsh：查日志用 `/usr/bin/log`（`log` 是 zsh 内建命令）；zsh 数组下标从 1 开始。
- 测试不得依赖"屏幕录制"授权，不得读写真实的系统剪切板（用 `NSPasteboard(name:)`）、真实的桌面（保存测试一律用临时目录）、用户真实的剪切板数据库。
- 坐标系（spec §4.4）：CG 全局 = 主屏左上角原点、y 向下（`CGWindowList`、`CGDisplayBounds`）；AppKit 全局 = 主屏左下角原点、y 向上（`NSScreen.frame`、窗口 frame）；遮罩内部统一用**屏内坐标**（该屏左上角原点、y 向下、pt），只有创建贴图窗口时才换算回 AppKit 全局。
- Vision 在一个新签名 / 新进程身份下第一次识别要加载模型，`TextRecognizerTests` 首次运行可能要 20 多秒，之后约 0.3 秒，属正常。
- 每个任务结束时 `scripts/test.sh` 必须全绿、零编译警告，然后提交。分支：`feat/screenshot`。

## File Structure

```
Package.swift                                        Task 3、7 修改
README.md                                            Task 7 整体替换

Sources/Core/
  KeyCombo.swift                 新  组合键 + 匹配（纯函数）
  GlobalKeyTap.swift             改名自 ModifierEventTap.swift；新增 register(combo) 与吞键
  ImageEncoding.swift            新  CGImage → PNG / TIFF（带 DPI）
  PasteService.swift             改  + originMarkerType、writeFromMyKit、write(image:)
  Permissions.swift              改  + 屏幕录制检查 / 申请 / 打开设置 / relaunch
  Toast.swift                    新  右上角小提示

Sources/ClipboardModule/
  ClipboardMonitor.swift         改  带 origin 标记的内容，来源记为 MyKit

Sources/ScreenshotModule/        全部新增
  ScreenGeometry.swift           屏内坐标 → AppKit 全局坐标
  WindowLocator.swift            窗口边框查询 + 纯函数（换算、命中）
  SelectionModel.swift           选区状态机
  ToolbarPlacement.swift         工具条 / 尺寸标签的位置
  ImageCropper.swift             按选区裁剪（含 Retina 倍数）
  ScreenshotSettings.swift       保存文件夹
  ScreenshotFileNamer.swift      文件名与重名处理
  ScreenshotSaver.swift          写 PNG，失败回退桌面
  TextRecognizer.swift           Vision OCR + 行排序
  CaptureAction.swift            操作枚举 + 键盘映射
  DisplaySnapshot.swift          ScreenDescriptor / DisplaySnapshot / CaptureResult
  ScreenCapturer.swift           ScreenCaptureKit 截全屏
  CaptureToolbar.swift           工具条
  OverlayView.swift              遮罩视图（绘制 + 鼠标）
  CaptureOverlayController.swift OverlayPanel + 一次截图会话
  PinZoom.swift                  贴图缩放（纯函数）
  PinWindow.swift                贴图窗口
  PinManager.swift               贴图集合
  OCRResultModel.swift           识别结果窗口的状态
  OCRResultWindowController.swift 识别结果窗口
  ScreenshotActions.swift        复制 / 保存 / 识别 / 贴图 的执行
  ScreenRecordingGuideWindowController.swift  授权引导
  ScreenshotSettingsView.swift   设置页
  ScreenshotModule.swift         AppModule 实现

Sources/MyKit/AppDelegate.swift  Task 1（改名）、Task 7（接线）修改

Tests/CoreTests/                 + KeyComboMatcherTests、ImageEncodingTests、ToastTests；PasteServiceTests 增补
Tests/ClipboardModuleTests/      ClipboardMonitorTests 增补
Tests/ScreenshotModuleTests/     全部新增
```

任务顺序：1 组合键与吞键 → 2 Core 增补 → 3 几何与选区 → 4 文件与 OCR → 5 截屏与遮罩 → 6 贴图、识别窗口、操作 → 7 总装与验收。

本计划里凡是"修改已有文件"的步骤，给出的都是**修改后的完整文件内容**，直接整体覆盖即可。

---

### Task 1: Core —— 组合键匹配，键盘监听支持注册组合键并吞键

**Files:**
- Create: `Sources/Core/KeyCombo.swift`
- Rename + Modify: `Sources/Core/ModifierEventTap.swift` → `Sources/Core/GlobalKeyTap.swift`
- Modify: `Sources/MyKit/AppDelegate.swift`
- Test: `Tests/CoreTests/KeyComboMatcherTests.swift`

**Interfaces:**
- Consumes: `DoubleTapDetector`、`ModifierEventTranslator`（已有）
- Produces:
  - `public struct KeyCombo: Equatable { public let keyCode: Int64; public let modifiers: CGEventFlags; public init(keyCode:modifiers:); public static let controlCommandA }`
  - `public enum KeyComboMatcher { public static func matches(_ combo: KeyCombo, type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool }`
  - `public final class GlobalKeyTap { public var onDoubleTap: (() -> Void)?; public var isRunning: Bool; public init(); public func register(_ combo: KeyCombo, handler: @escaping () -> Void); @discardableResult public func start() -> Bool; public func stop() }`

对 spec §4.1 的细化：自动重复不放在 `KeyComboMatcher` 里判断，而是由 `GlobalKeyTap` 处理 —— 按住 `⌃⌘A` 不放产生的重复事件**同样吞掉**，但 handler 只在第一次按下时触发。这样前台 App 不会收到一串漏网的重复按键。

- [ ] **Step 1: 写失败的测试 `Tests/CoreTests/KeyComboMatcherTests.swift`**

```swift
import CoreGraphics
import Testing
@testable import Core

@Suite struct KeyComboMatcherTests {
    private let combo = KeyCombo.controlCommandA
    private let aKey: Int64 = 0

    @Test func controlCommandAIsKeyCodeZeroWithControlAndCommand() {
        #expect(combo.keyCode == 0)
        #expect(combo.modifiers == [.maskControl, .maskCommand])
    }

    @Test func matchesExactCombo() {
        #expect(KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: [.maskControl, .maskCommand]))
    }

    @Test func ignoresIrrelevantFlagsLikeCapsLockAndFn() {
        let flags: CGEventFlags = [.maskControl, .maskCommand, .maskAlphaShift, .maskSecondaryFn, .maskNonCoalesced]
        #expect(KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: flags))
    }

    @Test func doesNotMatchWithExtraModifier() {
        #expect(!KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: [.maskControl, .maskCommand, .maskShift]))
        #expect(!KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: [.maskControl, .maskCommand, .maskAlternate]))
    }

    @Test func doesNotMatchWithMissingModifier() {
        #expect(!KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: [.maskCommand]))
        #expect(!KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: []))
    }

    @Test func doesNotMatchOtherKeys() {
        #expect(!KeyComboMatcher.matches(combo, type: .keyDown, keyCode: 1, flags: [.maskControl, .maskCommand]))
    }

    @Test func onlyMatchesKeyDown() {
        #expect(!KeyComboMatcher.matches(combo, type: .keyUp, keyCode: aKey, flags: [.maskControl, .maskCommand]))
        #expect(!KeyComboMatcher.matches(combo, type: .flagsChanged, keyCode: aKey, flags: [.maskControl, .maskCommand]))
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'KeyCombo' in scope`

- [ ] **Step 3: 写 `Sources/Core/KeyCombo.swift`**

```swift
import CoreGraphics

/// 一个全局组合键，例如 ⌃⌘A。
public struct KeyCombo: Equatable {
    /// 虚拟键码（与键盘布局无关），A = 0
    public let keyCode: Int64
    /// 只使用 ⌘ ⌃ ⌥ ⇧ 四个修饰键
    public let modifiers: CGEventFlags

    public init(keyCode: Int64, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌃⌘A —— 截图
    public static let controlCommandA = KeyCombo(keyCode: 0, modifiers: [.maskControl, .maskCommand])
}

/// 判断一个键盘事件是否正好是某个组合键。纯函数。
public enum KeyComboMatcher {
    private static let relevantModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    /// 修饰键必须**完全相等**：多按或少按一个 ⌘⌃⌥⇧ 都不算；Caps Lock、fn 等不参与比较。
    public static func matches(_ combo: KeyCombo, type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard type == .keyDown, keyCode == combo.keyCode else { return false }
        return flags.intersection(relevantModifiers) == combo.modifiers
    }
}
```

- [ ] **Step 4: 把键盘监听改名并扩展**

先改文件名（保留 git 历史）：

```bash
git mv Sources/Core/ModifierEventTap.swift Sources/Core/GlobalKeyTap.swift
```

然后用下面的内容整体覆盖。

`Sources/Core/GlobalKeyTap.swift`:

```swift
import CoreGraphics
import Foundation
import os

/// 全局键盘监听：检测"双击 Option"，以及已注册的组合键（如 ⌃⌘A）。需要"辅助功能"授权。
/// 所有回调都发生在主线程（事件源加在主 RunLoop 上）。
public final class GlobalKeyTap {
    public var onDoubleTap: (() -> Void)?

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var detector = DoubleTapDetector()
    private var registrations: [(combo: KeyCombo, handler: () -> Void)] = []
    private let log = Logger(subsystem: "com.imiros.mykit", category: "hotkey")

    public init() {}

    public var isRunning: Bool { port != nil }

    /// 注册一个组合键。按下时调用 handler，并且**吞掉**这次按键（前台 App 收不到）。
    /// 可以在 start() 之前或之后调用。
    public func register(_ combo: KeyCombo, handler: @escaping () -> Void) {
        registrations.append((combo: combo, handler: handler))
    }

    /// 返回 false 表示创建失败（通常是还没有辅助功能授权）。
    @discardableResult
    public func start() -> Bool {
        if port != nil { return true }

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            if let userInfo {
                let tap = Unmanaged<GlobalKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
                if tap.handle(type: type, event: event) {
                    return nil   // 已注册的组合键：吞掉
                }
            }
            return Unmanaged.passUnretained(event)   // 其余事件原样放行
        }
        // .defaultTap 只需要"辅助功能"授权；.listenOnly 会额外要求"输入监控"，而且无法吞掉事件
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log.error("创建事件监听失败（未授予辅助功能权限？）")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        detector = DoubleTapDetector()
        return true
    }

    public func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(port)
        self.port = nil
        self.source = nil
    }

    /// 返回 true 表示这个事件要被吞掉。
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // 系统会在回调太慢或用户输入安全内容时停用监听，这里立刻重新启用
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if let translated = ModifierEventTranslator.translate(type: type, keyCode: keyCode, flags: flags),
           detector.handle(translated, at: ProcessInfo.processInfo.systemUptime) {
            onDoubleTap?()
        }

        for registration in registrations
        where KeyComboMatcher.matches(registration.combo, type: type, keyCode: keyCode, flags: flags) {
            // 按住不放产生的自动重复：照样吞掉，但只在第一次按下时触发
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                registration.handler()
            }
            return true
        }
        return false
    }
}
```

- [ ] **Step 5: 更新 `Sources/MyKit/AppDelegate.swift`（完整内容；只有 `ModifierEventTap()` → `GlobalKeyTap()` 这一处变化）**

```swift
import AppKit
import ClipboardModule
import Core
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.imiros.mykit", category: "app")
    private let registry = ModuleRegistry()
    private let eventTap = GlobalKeyTap()
    private let accessibilityWatcher = AccessibilityWatcher()
    private let onboarding = OnboardingWindowController()
    private var clipboard: ClipboardModule?
    private var statusBar: StatusBarController?
    private var settingsWindow: SettingsWindowController?
    private var eventTapFailed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let clipboard = try ClipboardModule(databaseURL: ClipboardModule.defaultDatabaseURL)
            clipboard.onPausedChange = { [weak self] _ in self?.refreshIcon() }
            registry.register(clipboard)
            self.clipboard = clipboard
        } catch {
            log.error("剪切板模块初始化失败: \(String(describing: error), privacy: .public)")
        }

        registry.startAll()
        for failure in registry.failures {
            log.error("模块 \(failure.id, privacy: .public) 启动失败: \(String(describing: failure.error), privacy: .public)")
        }

        let settingsWindow = SettingsWindowController(modules: registry.modules)
        self.settingsWindow = settingsWindow
        statusBar = StatusBarController(
            moduleMenuItems: registry.menuItems,
            onOpenSettings: { settingsWindow.show() }
        )

        eventTap.onDoubleTap = { [weak self] in
            self?.clipboard?.togglePanel()
        }
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

- [ ] **Step 6: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 95 tests in 15 suites passed`，没有 `warning:`（`--build-system native` 的 deprecated 提示除外）。

- [ ] **Step 7: Commit**

```bash
git add -A Sources/Core Sources/MyKit/AppDelegate.swift Tests/CoreTests/KeyComboMatcherTests.swift
git commit -m "feat(core): key combo matching; GlobalKeyTap registers combos and swallows them"
```

---

### Task 2: Core 增补 —— 图片 / 来源标记写剪切板、屏幕录制权限、Toast；剪切板监听识别 MyKit 来源

**Files:**
- Create: `Sources/Core/ImageEncoding.swift`, `Sources/Core/Toast.swift`
- Modify: `Sources/Core/PasteService.swift`, `Sources/Core/Permissions.swift`, `Sources/ClipboardModule/ClipboardMonitor.swift`
- Test: `Tests/CoreTests/ImageEncodingTests.swift`, `Tests/CoreTests/ToastTests.swift`；增补 `Tests/CoreTests/PasteServiceTests.swift`, `Tests/ClipboardModuleTests/ClipboardMonitorTests.swift`

**Interfaces:**
- Consumes: 已有的 `PasteService`、`Permissions`、`ClipboardMonitor`、`CaptureFilter`
- Produces:
  - `public enum ImageEncoding { static func pngData(from: CGImage, pointSize: CGSize) -> Data?; static func tiffData(from: CGImage, pointSize: CGSize) -> Data? }`
  - `PasteService.originMarkerType: NSPasteboard.PasteboardType`（`"com.imiros.mykit.origin"`）
  - `PasteService.writeFromMyKit(_ text: String, to: NSPasteboard = .general)` —— 写文本 + 来源标记，**不带** own-write 标记，所以会作为新记录进入剪切板历史
  - `@discardableResult PasteService.write(image: CGImage, pointSize: CGSize, to: NSPasteboard = .general) -> Bool` —— PNG + TIFF
  - `Permissions.isScreenRecordingGranted: Bool`、`@discardableResult Permissions.requestScreenRecording() -> Bool`、`Permissions.openScreenRecordingSettings()`、`@MainActor Permissions.relaunch()`
  - `@MainActor public enum Toast { static func show(_ message: String, duration: TimeInterval = 1.5); nonisolated static func frame(for: CGSize, inVisibleFrame: CGRect) -> CGRect }`
  - `ClipboardMonitor`：剪切板类型里含 `com.imiros.mykit.origin` 时，来源记为 `(bundleID: "com.imiros.mykit", name: "MyKit")`

- [ ] **Step 1: 写失败的测试（两个新文件 + 两个增补后的完整文件）**

`Tests/CoreTests/ImageEncodingTests.swift`:

```swift
import AppKit
import Testing
@testable import Core

@Suite struct ImageEncodingTests {
    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @Test func pngKeepsPixelSizeAndRecordsPointSize() throws {
        let image = try makeImage(width: 200, height: 100)

        let data = try #require(ImageEncoding.pngData(from: image, pointSize: CGSize(width: 100, height: 50)))
        let decoded = try #require(NSBitmapImageRep(data: data))

        #expect(decoded.pixelsWide == 200)
        #expect(decoded.pixelsHigh == 100)
        #expect(abs(decoded.size.width - 100) < 0.5)    // 144 DPI → 按 pt 尺寸显示
        #expect(abs(decoded.size.height - 50) < 0.5)
    }

    @Test func zeroPointSizeFallsBackToPixelSize() throws {
        let image = try makeImage(width: 30, height: 20)
        let data = try #require(ImageEncoding.pngData(from: image, pointSize: .zero))
        let decoded = try #require(NSBitmapImageRep(data: data))
        #expect(decoded.pixelsWide == 30)
        #expect(decoded.pixelsHigh == 20)
    }

    @Test func tiffIsProduced() throws {
        let image = try makeImage(width: 10, height: 10)
        #expect(ImageEncoding.tiffData(from: image, pointSize: CGSize(width: 10, height: 10)) != nil)
    }
}
```

`Tests/CoreTests/ToastTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import Core

@Suite struct ToastTests {
    @Test func frameSitsInTopRightCornerOfVisibleArea() {
        let visible = CGRect(x: 0, y: 0, width: 1600, height: 975)
        let frame = Toast.frame(for: CGSize(width: 120, height: 36), inVisibleFrame: visible)

        #expect(frame.size == CGSize(width: 120, height: 36))
        #expect(frame.maxX == 1584)   // 1600 - 16；注意 #expect 里不要写字面量算式，宏展开后类型推断会出错
        #expect(frame.maxY == 963)    // 975 - 12
    }

    @Test func frameRespectsSecondaryScreenOrigin() {
        let visible = CGRect(x: 1600, y: -300, width: 1200, height: 800)
        let frame = Toast.frame(for: CGSize(width: 100, height: 30), inVisibleFrame: visible)

        #expect(frame.maxX == visible.maxX - 16)
        #expect(frame.maxY == visible.maxY - 12)
    }
}
```

`Tests/CoreTests/PasteServiceTests.swift`（完整内容；新增 `writeFromMyKit…` 和 `writeImage…` 两个测试）:

```swift
import AppKit
import Testing
@testable import Core

@Suite struct PasteServiceTests {
    @Test func writePutsTextAndOwnMarkerOnPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("mykit-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        PasteService.write("你好 MyKit", to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "你好 MyKit")
        #expect(pasteboard.types?.contains(PasteService.ownWriteType) == true)
    }

    @Test func writeReplacesPreviousContent() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("mykit-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        PasteService.write("first", to: pasteboard)
        let countAfterFirst = pasteboard.changeCount
        PasteService.write("second", to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "second")
        #expect(pasteboard.changeCount > countAfterFirst)
    }

    @Test func writeFromMyKitCarriesOriginMarkerButNotOwnWriteMarker() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("mykit-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        PasteService.writeFromMyKit("识别出来的文字", to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "识别出来的文字")
        #expect(pasteboard.types?.contains(PasteService.originMarkerType) == true)
        #expect(pasteboard.types?.contains(PasteService.ownWriteType) == false)
        #expect(PasteService.originMarkerType.rawValue == "com.imiros.mykit.origin")
    }

    @Test func writeImagePutsPNGAndTIFFOnPasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("mykit-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let context = try #require(CGContext(
            data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let image = try #require(context.makeImage())

        let ok = PasteService.write(image: image, pointSize: CGSize(width: 20, height: 10), to: pasteboard)

        #expect(ok)
        let png = try #require(pasteboard.data(forType: .png))
        let decoded = try #require(NSBitmapImageRep(data: png))
        #expect(decoded.pixelsWide == 40)
        #expect(decoded.pixelsHigh == 20)
        #expect(pasteboard.data(forType: .tiff) != nil)
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test func ownWriteTypeMatchesTheSpecIdentifier() {
        #expect(PasteService.ownWriteType.rawValue == "com.imiros.mykit.own-write")
    }
}
```

`Tests/ClipboardModuleTests/ClipboardMonitorTests.swift`（完整内容；新增 `contentWithMyKitOriginMarker…` 一个测试）:

```swift
import Foundation
import Testing
@testable import ClipboardModule

private final class FakePasteboard: PasteboardReading {
    var changeCount = 0
    var types: [String] = []
    var text: String?

    func currentTypeIdentifiers() -> [String] { types }
    func currentString() -> String? { text }

    func copy(_ string: String, extraTypes: [String] = []) {
        text = string
        types = ["public.utf8-plain-text"] + extraTypes
        changeCount += 1
    }
}

@MainActor
@Suite struct ClipboardMonitorTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeMonitor(
        _ pasteboard: FakePasteboard,
        _ store: ClipboardStore,
        now: @escaping () -> Date
    ) -> ClipboardMonitor {
        ClipboardMonitor(
            pasteboard: pasteboard,
            store: store,
            frontmostApp: { (bundleID: "com.apple.Safari", name: "Safari") },
            now: now
        )
    }

    @Test func recordsNewCopyWithSourceApp() async throws {
        let pasteboard = FakePasteboard()
        let store = try ClipboardStore(location: .inMemory)
        let monitor = makeMonitor(pasteboard, store, now: { self.t0 })

        pasteboard.copy("hello")
        await monitor.poll()

        let items = try await store.search(query: "", limit: 10, offset: 0)
        #expect(items.map(\.text) == ["hello"])
        #expect(items.first?.appName == "Safari")
        #expect(items.first?.appBundleID == "com.apple.Safari")
        #expect(items.first?.lastUsedAt == t0)
    }

    @Test func doesNothingWhenChangeCountUnchanged() async throws {
        let pasteboard = FakePasteboard()
        let store = try ClipboardStore(location: .inMemory)
        let monitor = makeMonitor(pasteboard, store, now: { self.t0 })

        pasteboard.copy("once")
        await monitor.poll()
        pasteboard.text = "changed without bumping changeCount"
        await monitor.poll()

        let items = try await store.search(query: "", limit: 10, offset: 0)
        #expect(items.map(\.text) == ["once"])
    }

    @Test func ignoresContentAlreadyOnPasteboardAtCreation() async throws {
        let pasteboard = FakePasteboard()
        pasteboard.copy("copied before MyKit launched")
        let store = try ClipboardStore(location: .inMemory)
        let monitor = makeMonitor(pasteboard, store, now: { self.t0 })

        await monitor.poll()

        let count = try await store.count()
        #expect(count == 0)
    }

    @Test func pausedMonitorSkipsContentEvenAfterResuming() async throws {
        let pasteboard = FakePasteboard()
        let store = try ClipboardStore(location: .inMemory)
        let monitor = makeMonitor(pasteboard, store, now: { self.t0 })

        monitor.isPaused = true
        pasteboard.copy("secret while paused")
        await monitor.poll()
        monitor.isPaused = false
        await monitor.poll()
        pasteboard.copy("after resume")
        await monitor.poll()

        let items = try await store.search(query: "", limit: 10, offset: 0)
        #expect(items.map(\.text) == ["after resume"])
    }

    @Test func skipsConcealedContent() async throws {
        let pasteboard = FakePasteboard()
        let store = try ClipboardStore(location: .inMemory)
        let monitor = makeMonitor(pasteboard, store, now: { self.t0 })

        pasteboard.copy("hunter2", extraTypes: ["org.nspasteboard.ConcealedType"])
        await monitor.poll()

        let count = try await store.count()
        #expect(count == 0)
    }

    @Test func contentWithMyKitOriginMarkerIsRecordedWithMyKitAsSource() async throws {
        let pasteboard = FakePasteboard()
        let store = try ClipboardStore(location: .inMemory)
        let monitor = makeMonitor(pasteboard, store, now: { self.t0 })

        pasteboard.copy("截图里识别出来的文字", extraTypes: ["com.imiros.mykit.origin"])
        await monitor.poll()

        let items = try await store.search(query: "", limit: 10, offset: 0)
        #expect(items.map(\.text) == ["截图里识别出来的文字"])
        #expect(items.first?.appBundleID == "com.imiros.mykit")
        #expect(items.first?.appName == "MyKit")
    }

    @Test func ownWriteMovesExistingItemToTopWithoutDuplicating() async throws {
        let pasteboard = FakePasteboard()
        let store = try ClipboardStore(location: .inMemory)
        var clock = t0
        let monitor = makeMonitor(pasteboard, store, now: { clock })

        pasteboard.copy("first")
        await monitor.poll()
        clock = t0.addingTimeInterval(5)
        pasteboard.copy("second")
        await monitor.poll()
        clock = t0.addingTimeInterval(10)
        pasteboard.copy("first", extraTypes: [CaptureFilter.ownWriteType])
        await monitor.poll()

        let items = try await store.search(query: "", limit: 10, offset: 0)
        #expect(items.map(\.text) == ["first", "second"])
        #expect(items.first?.lastUsedAt == t0.addingTimeInterval(10))
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'ImageEncoding' in scope`、`type 'PasteService' has no member 'writeFromMyKit'` 等。

- [ ] **Step 3: 写 Core 的实现（两个新文件 + 两个修改后的完整文件）**

`Sources/Core/ImageEncoding.swift`:

```swift
import AppKit

/// CGImage → PNG / TIFF 数据。pointSize 决定写入的 DPI：
/// Retina 屏上 200×100 像素、100×50 pt 的截图会标成 144 DPI，在"预览"里按 100×50 pt 显示。
public enum ImageEncoding {
    public static func pngData(from image: CGImage, pointSize: CGSize) -> Data? {
        bitmap(from: image, pointSize: pointSize).representation(using: .png, properties: [:])
    }

    public static func tiffData(from image: CGImage, pointSize: CGSize) -> Data? {
        bitmap(from: image, pointSize: pointSize).tiffRepresentation
    }

    private static func bitmap(from image: CGImage, pointSize: CGSize) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(cgImage: image)
        if pointSize.width > 0, pointSize.height > 0 {
            rep.size = pointSize
        }
        return rep
    }
}
```

`Sources/Core/PasteService.swift`（完整内容）:

```swift
import AppKit
import CoreGraphics

public enum PasteService {
    /// 写入剪切板时附带的标记，剪切板监听据此识别"这是 MyKit 自己写的"。
    public static let ownWriteType = NSPasteboard.PasteboardType("com.imiros.mykit.own-write")

    /// 由 MyKit 其他功能（例如截图的文字识别）产生的文字会带这个标记；
    /// 剪切板监听据此把来源记为 MyKit 自己，而不是当时碰巧在前台的 App。
    public static let originMarkerType = NSPasteboard.PasteboardType("com.imiros.mykit.origin")

    public static func write(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, ownWriteType], owner: nil)
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("1", forType: ownWriteType)
    }

    /// 写入一段由 MyKit 自己产生的文字。与 write(_:to:) 不同：它**会**作为新记录进入剪切板历史。
    public static func writeFromMyKit(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, originMarkerType], owner: nil)
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("1", forType: originMarkerType)
    }

    /// 写入一张图片（PNG + TIFF 两种格式，兼容各种 App）。pointSize 是图片的 pt 尺寸，用来写入正确的 DPI。
    @discardableResult
    public static func write(image: CGImage, pointSize: CGSize, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let png = ImageEncoding.pngData(from: image, pointSize: pointSize) else { return false }
        let tiff = ImageEncoding.tiffData(from: image, pointSize: pointSize)
        pasteboard.clearContents()
        pasteboard.declareTypes(tiff == nil ? [.png] : [.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        if let tiff {
            pasteboard.setData(tiff, forType: .tiff)
        }
        return true
    }

    /// 向系统事件流发送一次 ⌘V。需要"辅助功能"授权。
    public static func sendPasteKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// 写剪切板，稍等片刻（让面板先关闭、焦点回到原 App），再发送 ⌘V。
    public static func paste(_ text: String, delay: TimeInterval = 0.05) {
        write(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            sendPasteKeystroke()
        }
    }
}
```

`Sources/Core/Permissions.swift`（完整内容；`AccessibilityWatcher` 原样保留）:

```swift
import AppKit
import ApplicationServices

public enum Permissions {
    /// "辅助功能"授权：监听双击 Option 和模拟 ⌘V 都需要它。
    public static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    public static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// macOS 15.4 起，系统可以限制 App 在后台读取剪切板。为 true 时需要用户到
    /// "隐私与安全性 → 从其他 App 粘贴"里把 MyKit 设为"允许"。
    public static var pasteboardNeedsUserApproval: Bool {
        if #available(macOS 15.4, *) {
            switch NSPasteboard.general.accessBehavior {
            case .ask, .alwaysDeny:
                return true
            default:
                return false
            }
        }
        return false
    }

    /// "屏幕录制"授权：截图需要它。授权后必须重启 App 才生效。
    public static var isScreenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 第一次调用会弹出系统提示，并让 MyKit 出现在系统设置的"录屏与系统录音"列表里。
    @discardableResult
    public static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// 重新启动 MyKit：先拉起一个新实例，再退出当前实例。
    @MainActor
    public static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    public static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        NSWorkspace.shared.open(url)
    }
}

/// 每秒检查一次辅助功能授权，变化时回调。用户在系统设置里勾选后无需重启 MyKit。
@MainActor
public final class AccessibilityWatcher {
    public var onChange: ((Bool) -> Void)?
    public private(set) var isTrusted: Bool

    private let check: () -> Bool
    private var timer: Timer?

    public init(check: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.check = check
        self.isTrusted = check()
    }

    public func start(interval: TimeInterval = 1.0) {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func poll() {
        let current = check()
        guard current != isTrusted else { return }
        isTrusted = current
        onChange?(current)
    }
}
```

`Sources/Core/Toast.swift`:

```swift
import AppKit

/// 屏幕右上角的小提示（"已复制"之类），约 1.5 秒后淡出。不抢焦点、不挡鼠标。
@MainActor
public enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    /// 提示框位置：可见区域的右上角，距右边 16pt、距顶边 12pt。
    public nonisolated static func frame(for size: CGSize, inVisibleFrame visible: CGRect) -> CGRect {
        CGRect(
            x: visible.maxX - size.width - 16,
            y: visible.maxY - size.height - 12,
            width: size.width,
            height: size.height
        )
    }

    public static func show(_ message: String, duration: TimeInterval = 1.5) {
        hideWork?.cancel()
        panel?.orderOut(nil)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.sizeToFit()
        let size = CGSize(width: label.frame.width + 32, height: label.frame.height + 20)

        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        label.frame.origin = CGPoint(x: 16, y: 10)
        background.addSubview(label)

        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = background

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let screen {
            panel.setFrame(frame(for: size, inVisibleFrame: screen.visibleFrame), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        self.panel = panel

        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                guard let current = Toast.panel, current === panel else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    current.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated {
                        current.orderOut(nil)
                        if Toast.panel === current { Toast.panel = nil }
                    }
                })
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
```

- [ ] **Step 4: 更新 `Sources/ClipboardModule/ClipboardMonitor.swift`（完整内容；新增 `import Core`、`myKitApp`、来源判断）**

```swift
import AppKit
import Core
import os

/// 对系统剪切板的只读抽象，测试里用假实现替换。
public protocol PasteboardReading: AnyObject {
    var changeCount: Int { get }
    func currentTypeIdentifiers() -> [String]
    func currentString() -> String?
}

extension NSPasteboard: PasteboardReading {
    public func currentTypeIdentifiers() -> [String] {
        (types ?? []).map(\.rawValue)
    }

    public func currentString() -> String? {
        string(forType: .string)
    }
}

/// macOS 没有剪切板变更通知，只能定时比较 changeCount。
@MainActor
public final class ClipboardMonitor {
    /// 暂停时照常同步 changeCount，但不读取内容，所以暂停期间复制的东西恢复后也不会被补记。
    public var isPaused = false

    private let pasteboard: PasteboardReading
    private let store: ClipboardStore
    private let frontmostApp: () -> (bundleID: String?, name: String?)
    private let now: () -> Date
    private var lastChangeCount: Int
    private var timer: Timer?
    private let log = Logger(subsystem: "com.imiros.mykit", category: "clipboard")

    /// 带 MyKit 来源标记的内容记到这个来源名下
    static let myKitApp: (bundleID: String?, name: String?) = (bundleID: "com.imiros.mykit", name: "MyKit")

    public init(
        pasteboard: PasteboardReading,
        store: ClipboardStore,
        frontmostApp: @escaping () -> (bundleID: String?, name: String?) = {
            let app = NSWorkspace.shared.frontmostApplication
            return (bundleID: app?.bundleIdentifier, name: app?.localizedName)
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.pasteboard = pasteboard
        self.store = store
        self.frontmostApp = frontmostApp
        self.now = now
        self.lastChangeCount = pasteboard.changeCount   // 启动前就在剪切板里的内容不记录
    }

    public func start(interval: TimeInterval = 0.5) {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.poll()
            }
        }
        timer.tolerance = interval / 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func poll() async {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current          // 先同步再 await，重叠的 poll 不会重复处理同一次变化
        guard !isPaused else { return }

        let types = pasteboard.currentTypeIdentifiers()
        let decision = CaptureFilter.decide(types: types, string: pasteboard.currentString())
        do {
            switch decision {
            case .record(let text):
                // MyKit 自己产生的文字（如截图的文字识别结果）：来源记为 MyKit，而不是当时的前台 App
                let app = types.contains(PasteService.originMarkerType.rawValue) ? Self.myKitApp : frontmostApp()
                try await store.add(text: text, appBundleID: app.bundleID, appName: app.name, at: now())
            case .touchOwn(let text):
                try await store.touch(text: text, at: now())
            case .skip:
                break
            }
        } catch {
            // 单次写库失败：记日志、丢弃这一条，不打断监听
            log.error("写入剪切板历史失败: \(String(describing: error), privacy: .public)")
        }
    }
}
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 103 tests in 17 suites passed`，零警告。

- [ ] **Step 6: Commit**

```bash
git add Sources/Core Sources/ClipboardModule/ClipboardMonitor.swift Tests/CoreTests Tests/ClipboardModuleTests/ClipboardMonitorTests.swift
git commit -m "feat(core): image/origin pasteboard writes, screen recording permission helpers, toast; monitor credits MyKit-origin text"
```

---

### Task 3: ScreenshotModule Target + 纯几何逻辑（窗口定位、选区状态机、工具条位置、裁剪）

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ScreenshotModule/ScreenGeometry.swift`, `Sources/ScreenshotModule/WindowLocator.swift`, `Sources/ScreenshotModule/SelectionModel.swift`, `Sources/ScreenshotModule/ToolbarPlacement.swift`, `Sources/ScreenshotModule/ImageCropper.swift`
- Test: `Tests/ScreenshotModuleTests/ScreenGeometryTests.swift`, `Tests/ScreenshotModuleTests/WindowLocatorTests.swift`, `Tests/ScreenshotModuleTests/SelectionModelTests.swift`, `Tests/ScreenshotModuleTests/ToolbarPlacementTests.swift`, `Tests/ScreenshotModuleTests/ImageCropperTests.swift`

**Interfaces:**
- Consumes: 无
- Produces（全部是屏内坐标，除非注明）:
  - `ScreenGeometry.appKitRect(fromLocal: CGRect, screenFrame: CGRect) -> CGRect`
  - `WindowLocator.localRect(cgBounds:displayBounds:) -> CGRect?`、`localRects(cgWindows:displayBounds:) -> [CGRect]`、`topWindow(at:in:) -> CGRect?`、`parse(_:excludingPID:) -> [CGRect]`、`visibleWindowBounds() -> [CGRect]`（CG 全局，前 → 后）
  - `public struct SelectionModel`：`init(bounds:windows:)`；输入 `mouseMoved(to:)`、`mouseDown(at:)`、`mouseDragged(to:)`、`mouseUp(at:)`、`cancel() -> Bool`（true = 应退出截图）、`reset()`；输出 `selection: CGRect?`、`highlight: CGRect?`、`hasConfirmedSelection: Bool`、`isAdjusting: Bool`、`handle(at:) -> Handle?`、`static handlePoints(for:)`；常量 `dragThreshold = 3`、`minimumSize = 8`、`handleHitRadius = 6`
  - `ToolbarPlacement.toolbarOrigin(toolbarSize:selection:bounds:gap:) -> CGPoint`、`labelOrigin(labelSize:selection:bounds:gap:) -> CGPoint`
  - `ImageCropper.crop(_ image: CGImage, rect: CGRect, scale: CGFloat) -> CGImage?`

对 spec §2.2 的细化：选区确定后，在选区**外**按住拖动 → 重新框一个新选区；在选区外单击 → 保持原选区不变。

- [ ] **Step 1: 更新 `Package.swift`（完整内容；新增 `ScreenshotModule` 与其测试 Target，`MyKit` 暂不依赖它）**

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
        .executableTarget(name: "MyKit", dependencies: ["Core", "ClipboardModule"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "ClipboardModuleTests", dependencies: ["ClipboardModule"]),
        .testTarget(name: "ScreenshotModuleTests", dependencies: ["ScreenshotModule"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: 写失败的测试（五个文件）**

`Tests/ScreenshotModuleTests/ScreenGeometryTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct ScreenGeometryTests {
    @Test func convertsLocalTopLeftRectToAppKitBottomLeftRect() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let local = CGRect(x: 100, y: 50, width: 300, height: 200)

        let result = ScreenGeometry.appKitRect(fromLocal: local, screenFrame: screen)

        #expect(result == CGRect(x: 100, y: 750, width: 300, height: 200))   // y = 1000 - (50 + 200)
    }

    @Test func respectsSecondaryScreenOrigin() {
        let screen = CGRect(x: 1600, y: -200, width: 1200, height: 800)
        let local = CGRect(x: 10, y: 20, width: 100, height: 100)

        let result = ScreenGeometry.appKitRect(fromLocal: local, screenFrame: screen)

        #expect(result == CGRect(x: 1610, y: 480, width: 100, height: 100))  // y = (-200 + 800) - 120
    }
}
```

`Tests/ScreenshotModuleTests/WindowLocatorTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct WindowLocatorTests {
    private let display = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    private func info(layer: Int = 0, alpha: Double = 1, pid: pid_t = 100, bounds: CGRect) -> [String: Any] {
        [
            kCGWindowLayer as String: layer,
            kCGWindowAlpha as String: alpha,
            kCGWindowOwnerPID as String: pid,
            kCGWindowBounds as String: bounds.dictionaryRepresentation as NSDictionary,
        ]
    }

    @Test func localRectOnPrimaryDisplayIsUnchanged() {
        let rect = WindowLocator.localRect(cgBounds: CGRect(x: 100, y: 50, width: 800, height: 600), displayBounds: display)
        #expect(rect == CGRect(x: 100, y: 50, width: 800, height: 600))
    }

    @Test func localRectIsOffsetBySecondaryDisplayOrigin() {
        let second = CGRect(x: 1600, y: -200, width: 1200, height: 800)
        let rect = WindowLocator.localRect(cgBounds: CGRect(x: 1700, y: -100, width: 500, height: 400), displayBounds: second)
        #expect(rect == CGRect(x: 100, y: 100, width: 500, height: 400))
    }

    @Test func localRectIsClippedToDisplay() {
        let rect = WindowLocator.localRect(cgBounds: CGRect(x: -50, y: 900, width: 300, height: 300), displayBounds: display)
        #expect(rect == CGRect(x: 0, y: 900, width: 250, height: 100))
    }

    @Test func windowOnAnotherDisplayIsDropped() {
        #expect(WindowLocator.localRect(cgBounds: CGRect(x: 2000, y: 0, width: 300, height: 300), displayBounds: display) == nil)
        let rects = WindowLocator.localRects(
            cgWindows: [CGRect(x: 2000, y: 0, width: 300, height: 300), CGRect(x: 10, y: 10, width: 100, height: 100)],
            displayBounds: display
        )
        #expect(rects == [CGRect(x: 10, y: 10, width: 100, height: 100)])
    }

    @Test func topWindowIsTheFrontmostOneContainingThePoint() {
        let front = CGRect(x: 100, y: 100, width: 300, height: 300)
        let back = CGRect(x: 0, y: 0, width: 1000, height: 800)

        #expect(WindowLocator.topWindow(at: CGPoint(x: 200, y: 200), in: [front, back]) == front)
        #expect(WindowLocator.topWindow(at: CGPoint(x: 600, y: 600), in: [front, back]) == back)
        #expect(WindowLocator.topWindow(at: CGPoint(x: 1500, y: 900), in: [front, back]) == nil)
    }

    @Test func parseKeepsOnlyNormalVisibleForeignWindowsInOrder() {
        let list: [[String: Any]] = [
            info(layer: 24, bounds: CGRect(x: 0, y: 0, width: 1600, height: 24)),            // 菜单栏
            info(bounds: CGRect(x: 100, y: 100, width: 800, height: 600)),                   // 普通窗口（最前）
            info(alpha: 0, bounds: CGRect(x: 0, y: 0, width: 500, height: 500)),             // 全透明
            info(pid: 42, bounds: CGRect(x: 0, y: 0, width: 700, height: 700)),              // MyKit 自己
            info(bounds: CGRect(x: 5, y: 5, width: 30, height: 30)),                         // 太小
            info(bounds: CGRect(x: 0, y: 30, width: 1600, height: 900)),                     // 普通窗口（靠后）
        ]

        let result = WindowLocator.parse(list, excludingPID: 42)

        #expect(result == [
            CGRect(x: 100, y: 100, width: 800, height: 600),
            CGRect(x: 0, y: 30, width: 1600, height: 900),
        ])
    }

    @Test func parseSkipsEntriesWithoutBounds() {
        let broken: [String: Any] = [kCGWindowLayer as String: 0]
        #expect(WindowLocator.parse([broken], excludingPID: 1).isEmpty)
    }

    @Test func systemQueryRunsWithoutScreenRecordingPermission() {
        // 只验证不崩溃、结果满足过滤条件；不依赖当前开着哪些窗口
        for bounds in WindowLocator.visibleWindowBounds() {
            #expect(bounds.width >= WindowLocator.minimumWindowSide)
            #expect(bounds.height >= WindowLocator.minimumWindowSide)
        }
    }
}
```

`Tests/ScreenshotModuleTests/SelectionModelTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct SelectionModelTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let frontWindow = CGRect(x: 100, y: 100, width: 400, height: 300)
    private let backWindow = CGRect(x: 0, y: 0, width: 900, height: 700)

    private func makeModel() -> SelectionModel {
        SelectionModel(bounds: bounds, windows: [frontWindow, backWindow])
    }

    /// 拖出一个选区并松手。
    private func makeSelected(from start: CGPoint, to end: CGPoint) -> SelectionModel {
        var model = makeModel()
        model.mouseDown(at: start)
        model.mouseDragged(to: end)
        model.mouseUp(at: end)
        return model
    }

    // MARK: 悬停与单击选窗

    @Test func hoveringHighlightsTopWindowUnderMouse() {
        var model = makeModel()
        model.mouseMoved(to: CGPoint(x: 200, y: 200))
        #expect(model.highlight == frontWindow)
        #expect(model.selection == nil)
        #expect(!model.hasConfirmedSelection)

        model.mouseMoved(to: CGPoint(x: 700, y: 600))
        #expect(model.highlight == backWindow)

        model.mouseMoved(to: CGPoint(x: 950, y: 750))
        #expect(model.highlight == nil)
    }

    @Test func clickingWithoutDraggingSelectsHoveredWindow() {
        var model = makeModel()
        model.mouseDown(at: CGPoint(x: 200, y: 200))
        model.mouseDragged(to: CGPoint(x: 201, y: 201))     // 不足 3pt，仍算单击
        model.mouseUp(at: CGPoint(x: 201, y: 201))

        #expect(model.selection == frontWindow)
        #expect(model.hasConfirmedSelection)
        #expect(!model.isAdjusting)
    }

    @Test func clickingWhereThereIsNoWindowDoesNothing() {
        var model = makeModel()
        model.mouseDown(at: CGPoint(x: 950, y: 750))
        model.mouseUp(at: CGPoint(x: 950, y: 750))
        #expect(model.selection == nil)
        #expect(!model.hasConfirmedSelection)
    }

    // MARK: 框选

    @Test func draggingDrawsSelectionAndHidesToolbarUntilMouseUp() {
        var model = makeModel()
        model.mouseDown(at: CGPoint(x: 50, y: 60))
        model.mouseDragged(to: CGPoint(x: 250, y: 200))

        #expect(model.selection == CGRect(x: 50, y: 60, width: 200, height: 140))
        #expect(model.isAdjusting)
        #expect(!model.hasConfirmedSelection)

        model.mouseUp(at: CGPoint(x: 250, y: 200))
        #expect(model.selection == CGRect(x: 50, y: 60, width: 200, height: 140))
        #expect(model.hasConfirmedSelection)
        #expect(!model.isAdjusting)
    }

    @Test func draggingUpAndLeftIsNormalised() {
        let model = makeSelected(from: CGPoint(x: 300, y: 300), to: CGPoint(x: 100, y: 150))
        #expect(model.selection == CGRect(x: 100, y: 150, width: 200, height: 150))
    }

    @Test func selectionIsClampedToScreenAndRoundedToWholePoints() {
        let model = makeSelected(from: CGPoint(x: 900.4, y: 700.6), to: CGPoint(x: 1200, y: 900))
        #expect(model.selection == CGRect(x: 900, y: 701, width: 100, height: 99))
    }

    @Test func tooSmallSelectionIsDiscarded() {
        let model = makeSelected(from: CGPoint(x: 950, y: 750), to: CGPoint(x: 955, y: 790))   // 宽只有 5pt
        #expect(model.selection == nil)
        #expect(!model.hasConfirmedSelection)
    }

    @Test func hoverIsIgnoredOnceThereIsASelection() {
        var model = makeSelected(from: CGPoint(x: 600, y: 600), to: CGPoint(x: 700, y: 700))
        model.mouseMoved(to: CGPoint(x: 200, y: 200))
        #expect(model.highlight == CGRect(x: 600, y: 600, width: 100, height: 100))
    }

    // MARK: 移动

    @Test func draggingInsideMovesSelection() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        model.mouseDown(at: CGPoint(x: 200, y: 150))
        model.mouseDragged(to: CGPoint(x: 250, y: 180))
        #expect(model.isAdjusting)
        model.mouseUp(at: CGPoint(x: 250, y: 180))

        #expect(model.selection == CGRect(x: 150, y: 130, width: 200, height: 100))
        #expect(model.hasConfirmedSelection)
    }

    @Test func movingStopsAtScreenEdgesAndKeepsSize() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        model.mouseDown(at: CGPoint(x: 200, y: 150))
        model.mouseDragged(to: CGPoint(x: 5000, y: -5000))
        model.mouseUp(at: CGPoint(x: 5000, y: -5000))

        #expect(model.selection == CGRect(x: 800, y: 0, width: 200, height: 100))
    }

    // MARK: 缩放

    @Test func handlesAreOnlyAvailableOnConfirmedSelection() {
        var model = makeModel()
        #expect(model.handle(at: CGPoint(x: 100, y: 100)) == nil)

        model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        #expect(model.handle(at: CGPoint(x: 100, y: 100)) == .topLeft)
        #expect(model.handle(at: CGPoint(x: 200, y: 100)) == .top)
        #expect(model.handle(at: CGPoint(x: 304, y: 196)) == .bottomRight)    // 6pt 命中半径内
        #expect(model.handle(at: CGPoint(x: 300, y: 150)) == .right)
        #expect(model.handle(at: CGPoint(x: 200, y: 150)) == nil)             // 选区中间不是手柄
    }

    @Test func handlePointsCoverCornersAndEdgeMidpoints() {
        let points = SelectionModel.handlePoints(for: CGRect(x: 0, y: 0, width: 100, height: 60))
        #expect(points.count == 8)
        #expect(points.first { $0.handle == .bottom }?.point == CGPoint(x: 50, y: 60))
        #expect(points.first { $0.handle == .left }?.point == CGPoint(x: 0, y: 30))
    }

    @Test func draggingCornerHandleResizesTwoEdges() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        model.mouseDown(at: CGPoint(x: 300, y: 200))                 // 右下角
        model.mouseDragged(to: CGPoint(x: 400, y: 260))
        model.mouseUp(at: CGPoint(x: 400, y: 260))
        #expect(model.selection == CGRect(x: 100, y: 100, width: 300, height: 160))
    }

    @Test func draggingEdgeHandleResizesOnlyThatEdge() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        model.mouseDown(at: CGPoint(x: 200, y: 100))                 // 上边中点
        model.mouseDragged(to: CGPoint(x: 555, y: 40))               // 水平方向的移动被忽略
        model.mouseUp(at: CGPoint(x: 555, y: 40))
        #expect(model.selection == CGRect(x: 100, y: 40, width: 200, height: 160))
    }

    @Test func resizingCannotShrinkBelowMinimumOrFlip() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        model.mouseDown(at: CGPoint(x: 100, y: 150))                 // 左边中点
        model.mouseDragged(to: CGPoint(x: 900, y: 150))              // 拖过右边
        model.mouseUp(at: CGPoint(x: 900, y: 150))
        #expect(model.selection == CGRect(x: 292, y: 100, width: 8, height: 100))
    }

    @Test func resizingIsClampedToScreen() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        model.mouseDown(at: CGPoint(x: 100, y: 100))                 // 左上角
        model.mouseDragged(to: CGPoint(x: -400, y: -400))
        model.mouseUp(at: CGPoint(x: -400, y: -400))
        #expect(model.selection == CGRect(x: 0, y: 0, width: 300, height: 200))
    }

    // MARK: 选区外操作

    @Test func draggingOutsideSelectionStartsANewOne() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        model.mouseDown(at: CGPoint(x: 500, y: 500))
        model.mouseDragged(to: CGPoint(x: 650, y: 620))
        model.mouseUp(at: CGPoint(x: 650, y: 620))
        #expect(model.selection == CGRect(x: 500, y: 500, width: 150, height: 120))
    }

    @Test func clickingOutsideSelectionKeepsIt() {
        var model = makeSelected(from: CGPoint(x: 600, y: 600), to: CGPoint(x: 700, y: 700))
        model.mouseDown(at: CGPoint(x: 200, y: 200))                 // 这里有窗口，但已有选区时单击不换
        model.mouseUp(at: CGPoint(x: 200, y: 200))
        #expect(model.selection == CGRect(x: 600, y: 600, width: 100, height: 100))
        #expect(model.hasConfirmedSelection)
    }

    // MARK: 取消

    @Test func cancelFirstClearsSelectionThenAsksToExit() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))

        #expect(model.cancel() == false)
        #expect(model.selection == nil)
        #expect(model.highlight == nil)

        #expect(model.cancel() == true)
    }

    @Test func cancelWhileDraggingClearsWithoutExiting() {
        var model = makeModel()
        model.mouseDown(at: CGPoint(x: 100, y: 100))
        model.mouseDragged(to: CGPoint(x: 200, y: 200))
        #expect(model.cancel() == false)
        #expect(model.selection == nil)
        #expect(!model.isAdjusting)
    }

    @Test func resetClearsEverything() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        model.reset()
        #expect(model.selection == nil)
        #expect(!model.hasConfirmedSelection)
        #expect(model.cancel() == true)
    }
}
```

`Tests/ScreenshotModuleTests/ToolbarPlacementTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct ToolbarPlacementTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let toolbar = CGSize(width: 300, height: 40)
    private let label = CGSize(width: 90, height: 20)

    @Test func toolbarGoesBelowSelectionRightAligned() {
        let origin = ToolbarPlacement.toolbarOrigin(
            toolbarSize: toolbar, selection: CGRect(x: 200, y: 100, width: 500, height: 300), bounds: bounds)
        #expect(origin == CGPoint(x: 400, y: 408))       // x = 700 - 300；y = 400 + 8
    }

    @Test func toolbarGoesAboveWhenNoRoomBelow() {
        let origin = ToolbarPlacement.toolbarOrigin(
            toolbarSize: toolbar, selection: CGRect(x: 200, y: 400, width: 500, height: 380), bounds: bounds)
        #expect(origin == CGPoint(x: 400, y: 352))       // y = 400 - 8 - 40
    }

    @Test func toolbarGoesInsideWhenNoRoomAboveOrBelow() {
        let origin = ToolbarPlacement.toolbarOrigin(
            toolbarSize: toolbar, selection: CGRect(x: 0, y: 10, width: 1000, height: 780), bounds: bounds)
        #expect(origin == CGPoint(x: 692, y: 742))       // x = 1000 - 8 - 300；y = 790 - 8 - 40
    }

    @Test func toolbarNeverLeavesScreenHorizontally() {
        let origin = ToolbarPlacement.toolbarOrigin(
            toolbarSize: toolbar, selection: CGRect(x: 10, y: 100, width: 50, height: 50), bounds: bounds)
        #expect(origin == CGPoint(x: 0, y: 158))         // 60 - 300 < 0 → 贴左边
    }

    @Test func labelSitsAboveTopLeftCorner() {
        let origin = ToolbarPlacement.labelOrigin(
            labelSize: label, selection: CGRect(x: 200, y: 100, width: 500, height: 300), bounds: bounds)
        #expect(origin == CGPoint(x: 200, y: 76))        // y = 100 - 4 - 20
    }

    @Test func labelMovesInsideWhenSelectionTouchesTop() {
        let origin = ToolbarPlacement.labelOrigin(
            labelSize: label, selection: CGRect(x: 200, y: 10, width: 500, height: 300), bounds: bounds)
        #expect(origin == CGPoint(x: 204, y: 14))
    }

    @Test func labelStaysOnScreenAtRightEdge() {
        let origin = ToolbarPlacement.labelOrigin(
            labelSize: label, selection: CGRect(x: 980, y: 100, width: 20, height: 50), bounds: bounds)
        #expect(origin == CGPoint(x: 910, y: 76))
    }
}
```

`Tests/ScreenshotModuleTests/ImageCropperTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct ImageCropperTests {
    /// 200×100 像素：**上半部分红色、下半部分蓝色**（以图像左上角为原点描述）。
    private func makeImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // CGContext 的坐标原点在左下角：y 50…100 是图像的上半部分
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 50, width: 200, height: 50))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 50))
        return try #require(context.makeImage())
    }

    /// 取图像正中间那个像素的 (r, g, b)。
    private func centerPixel(of image: CGImage) throws -> [UInt8] {
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // 把图像平移，使其中心落在这个 1×1 的画布上
        context.draw(image, in: CGRect(
            x: -CGFloat(image.width) / 2 + 0.5, y: -CGFloat(image.height) / 2 + 0.5,
            width: CGFloat(image.width), height: CGFloat(image.height)
        ))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return [data[0], data[1], data[2]]
    }

    @Test func cropsInPixelsAtScaleOne() throws {
        let cropped = try #require(ImageCropper.crop(try makeImage(), rect: CGRect(x: 10, y: 5, width: 60, height: 30), scale: 1))
        #expect(cropped.width == 60)
        #expect(cropped.height == 30)
    }

    @Test func multipliesByScaleOnRetina() throws {
        let cropped = try #require(ImageCropper.crop(try makeImage(), rect: CGRect(x: 10, y: 5, width: 60, height: 30), scale: 2))
        #expect(cropped.width == 120)
        #expect(cropped.height == 60)
    }

    @Test func rectUsesTopLeftOrigin() throws {
        let image = try makeImage()
        let top = try #require(ImageCropper.crop(image, rect: CGRect(x: 0, y: 0, width: 200, height: 40), scale: 1))
        let bottom = try #require(ImageCropper.crop(image, rect: CGRect(x: 0, y: 60, width: 200, height: 40), scale: 1))

        let topColor = try centerPixel(of: top)
        let bottomColor = try centerPixel(of: bottom)
        // 颜色经过色彩空间换算后不是精确的 255/0，只判断主色
        #expect(topColor[0] > 200 && topColor[2] < 60)          // 上面是红色
        #expect(bottomColor[2] > 200 && bottomColor[0] < 60)    // 下面是蓝色
    }

    @Test func clipsToImageBounds() throws {
        let cropped = try #require(ImageCropper.crop(try makeImage(), rect: CGRect(x: 150, y: 80, width: 500, height: 500), scale: 1))
        #expect(cropped.width == 50)
        #expect(cropped.height == 20)
    }

    @Test func returnsNilWhenRectIsOutsideOrEmpty() throws {
        let image = try makeImage()
        #expect(ImageCropper.crop(image, rect: CGRect(x: 500, y: 500, width: 10, height: 10), scale: 1) == nil)
        #expect(ImageCropper.crop(image, rect: CGRect(x: 10, y: 10, width: 0, height: 0), scale: 1) == nil)
    }
}
```

- [ ] **Step 3: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败（`ScreenshotModule` 还没有源文件 / `cannot find 'SelectionModel' in scope`）。

- [ ] **Step 4: 写实现（五个文件）**

`Sources/ScreenshotModule/ScreenGeometry.swift`:

```swift
import CoreGraphics

/// 坐标系换算。截图遮罩内部统一用"屏内坐标"：某块屏幕的左上角为原点、y 向下、单位 pt。
public enum ScreenGeometry {
    /// 屏内坐标 → AppKit 全局坐标（主屏左下角为原点、y 向上）。screenFrame 是 NSScreen.frame。
    public static func appKitRect(fromLocal rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + rect.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
```

`Sources/ScreenshotModule/WindowLocator.swift`:

```swift
import CoreGraphics
import Foundation

/// 找出屏幕上的窗口边框，用于"鼠标移到窗口上自动高亮"。
/// 读取窗口边框不需要"屏幕录制"授权（读取窗口标题才需要，这里不读）。
public enum WindowLocator {
    /// 小于这个尺寸的窗口（各种小浮层）不参与识别
    public static let minimumWindowSide: CGFloat = 40

    /// CG 全局坐标（主屏左上角为原点、y 向下）→ 某块屏的屏内坐标，并裁到屏幕范围内。
    /// 窗口完全不在这块屏上时返回 nil。
    public static func localRect(cgBounds: CGRect, displayBounds: CGRect) -> CGRect? {
        let clipped = cgBounds.intersection(displayBounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        return clipped.offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY)
    }

    /// 批量换算，保持前后顺序（数组靠前 = 窗口靠前）。
    public static func localRects(cgWindows: [CGRect], displayBounds: CGRect) -> [CGRect] {
        cgWindows.compactMap { localRect(cgBounds: $0, displayBounds: displayBounds) }
    }

    /// 鼠标位置下最靠前的窗口。
    public static func topWindow(at point: CGPoint, in windows: [CGRect]) -> CGRect? {
        windows.first { $0.contains(point) }
    }

    /// 从 CGWindowListCopyWindowInfo 的结果里挑出普通窗口的边框（CG 全局坐标），保持前后顺序。
    public static func parse(_ list: [[String: Any]], excludingPID ownPID: pid_t) -> [CGRect] {
        list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0 else { return nil }          // 只要普通窗口层
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 { return nil }
            if let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == ownPID { return nil }   // 不识别 MyKit 自己的窗口
            guard let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else { return nil }
            guard bounds.width >= minimumWindowSide, bounds.height >= minimumWindowSide else { return nil }
            return bounds
        }
    }

    /// 当前屏幕上所有可见的普通窗口（CG 全局坐标，前 → 后）。
    public static func visibleWindowBounds() -> [CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
        return parse(list, excludingPID: ProcessInfo.processInfo.processIdentifier)
    }
}
```

`Sources/ScreenshotModule/SelectionModel.swift`:

```swift
import CoreGraphics

/// 截图选区的全部交互逻辑。纯状态机：输入鼠标事件，输出"选区 / 高亮 / 是否正在调整"。
/// 坐标一律是屏内坐标（左上角原点、y 向下、pt）。
public struct SelectionModel {
    public enum Handle: CaseIterable, Equatable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private enum State: Equatable {
        /// 还没有选区；鼠标下的窗口高亮
        case idle
        /// 鼠标已按下但还没拖够 3pt。previous 是按下前已有的选区（在选区外按下时）
        case pressing(start: CGPoint, previous: CGRect?)
        case drawing(start: CGPoint, current: CGPoint)
        case selected(CGRect)
        case moving(original: CGRect, grab: CGPoint, current: CGRect)
        case resizing(handle: Handle, original: CGRect, current: CGRect)
    }

    /// 按下到松开移动不足这个距离算"单击"
    public static let dragThreshold: CGFloat = 3
    public static let minimumSize: CGFloat = 8
    public static let handleHitRadius: CGFloat = 6

    /// 这块屏的范围：(0, 0, 宽, 高)
    public let bounds: CGRect
    /// 这块屏上的窗口（屏内坐标，前 → 后）
    public let windows: [CGRect]
    public private(set) var hoverWindow: CGRect?
    private var state: State = .idle

    public init(bounds: CGRect, windows: [CGRect]) {
        self.bounds = bounds
        self.windows = windows
    }

    // MARK: 输出

    /// 当前选区（含正在拖出 / 移动 / 缩放中的）。
    public var selection: CGRect? {
        switch state {
        case .idle: return nil
        case .pressing(_, let previous): return previous
        case .drawing(let start, let current): return Self.normalized(start, current)
        case .selected(let rect): return rect
        case .moving(_, _, let current): return current
        case .resizing(_, _, let current): return current
        }
    }

    /// 要"点亮"的区域：有选区就是选区，否则是鼠标下的窗口。
    public var highlight: CGRect? {
        selection ?? hoverWindow
    }

    /// 选区已经确定（可以显示手柄和工具条、可以执行复制等操作）。
    public var hasConfirmedSelection: Bool {
        if case .selected = state { return true }
        return false
    }

    /// 鼠标正按着（拖出 / 移动 / 缩放中）：此时隐藏工具条。
    public var isAdjusting: Bool {
        switch state {
        case .idle, .selected: return false
        case .pressing, .drawing, .moving, .resizing: return true
        }
    }

    /// 8 个手柄的中心点。
    public static func handlePoints(for rect: CGRect) -> [(handle: Handle, point: CGPoint)] {
        [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.top, CGPoint(x: rect.midX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY)),
        ]
    }

    /// 鼠标位置命中了哪个手柄（只有选区确定后才有手柄）。
    public func handle(at point: CGPoint) -> Handle? {
        guard case .selected(let rect) = state else { return nil }
        return Self.handlePoints(for: rect).first { candidate in
            abs(candidate.point.x - point.x) <= Self.handleHitRadius
                && abs(candidate.point.y - point.y) <= Self.handleHitRadius
        }?.handle
    }

    // MARK: 输入

    public mutating func mouseMoved(to point: CGPoint) {
        guard case .idle = state else { return }
        hoverWindow = WindowLocator.topWindow(at: point, in: windows)
    }

    public mutating func mouseDown(at point: CGPoint) {
        switch state {
        case .idle:
            hoverWindow = WindowLocator.topWindow(at: point, in: windows)
            state = .pressing(start: clamped(point), previous: nil)
        case .selected(let rect):
            if let handle = handle(at: point) {
                state = .resizing(handle: handle, original: rect, current: rect)
            } else if rect.contains(point) {
                state = .moving(original: rect, grab: point, current: rect)
            } else {
                state = .pressing(start: clamped(point), previous: rect)   // 选区外按下：可能要重新框选
            }
        case .pressing, .drawing, .moving, .resizing:
            break
        }
    }

    public mutating func mouseDragged(to point: CGPoint) {
        switch state {
        case .pressing(let start, _):
            let distance = hypot(point.x - start.x, point.y - start.y)
            if distance >= Self.dragThreshold {
                state = .drawing(start: start, current: clamped(point))
            }
        case .drawing(let start, _):
            state = .drawing(start: start, current: clamped(point))
        case .moving(let original, let grab, _):
            state = .moving(original: original, grab: grab, current: moved(original, by: point, from: grab))
        case .resizing(let handle, let original, _):
            state = .resizing(handle: handle, original: original, current: resized(original, handle: handle, to: clamped(point)))
        case .idle, .selected:
            break
        }
    }

    public mutating func mouseUp(at point: CGPoint) {
        switch state {
        case .pressing(let start, let previous):
            if let previous {
                state = .selected(previous)                       // 在选区外单击：保持原选区
            } else if let window = WindowLocator.topWindow(at: start, in: windows) {
                state = .selected(Self.rounded(window))           // 单击窗口：选中整个窗口
            } else {
                state = .idle
            }
        case .drawing(let start, let current):
            let rect = Self.normalized(start, current)
            if rect.width >= Self.minimumSize, rect.height >= Self.minimumSize {
                state = .selected(rect)
            } else {
                state = .idle                                     // 太小，当作没选
                hoverWindow = WindowLocator.topWindow(at: point, in: windows)
            }
        case .moving(_, _, let current), .resizing(_, _, let current):
            state = .selected(current)
        case .idle, .selected:
            break
        }
    }

    /// Esc / 右键。返回 true 表示"没有选区可清了，应该退出截图"。
    public mutating func cancel() -> Bool {
        if case .idle = state { return true }
        reset()
        return false
    }

    /// 回到初始状态（另一块屏开始操作时，这块屏的选区要清掉）。
    public mutating func reset() {
        state = .idle
        hoverWindow = nil
    }

    // MARK: 几何

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func moved(_ original: CGRect, by point: CGPoint, from grab: CGPoint) -> CGRect {
        let x = min(max(original.minX + point.x - grab.x, bounds.minX), bounds.maxX - original.width)
        let y = min(max(original.minY + point.y - grab.y, bounds.minY), bounds.maxY - original.height)
        return Self.rounded(CGRect(x: x, y: y, width: original.width, height: original.height))
    }

    private func resized(_ original: CGRect, handle: Handle, to point: CGPoint) -> CGRect {
        var minX = original.minX, maxX = original.maxX, minY = original.minY, maxY = original.maxY
        let minimum = Self.minimumSize
        switch handle {
        case .topLeft, .left, .bottomLeft: minX = min(point.x, maxX - minimum)
        case .topRight, .right, .bottomRight: maxX = max(point.x, minX + minimum)
        case .top, .bottom: break
        }
        switch handle {
        case .topLeft, .top, .topRight: minY = min(point.y, maxY - minimum)
        case .bottomLeft, .bottom, .bottomRight: maxY = max(point.y, minY + minimum)
        case .left, .right: break
        }
        return Self.rounded(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    private static func normalized(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        rounded(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)))
    }

    /// 四条边各自取整到整数 pt。
    private static func rounded(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded(), minY = rect.minY.rounded()
        let maxX = rect.maxX.rounded(), maxY = rect.maxY.rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
```

`Sources/ScreenshotModule/ToolbarPlacement.swift`:

```swift
import CoreGraphics

/// 工具条和尺寸标签放在哪。纯函数，屏内坐标（左上角原点），返回的是左上角位置。
public enum ToolbarPlacement {
    /// 优先选区下方右对齐；下方放不下 → 上方；上下都放不下 → 选区内右下角。水平方向始终不超出屏幕。
    public static func toolbarOrigin(toolbarSize: CGSize, selection: CGRect, bounds: CGRect, gap: CGFloat = 8) -> CGPoint {
        func clampedX(_ x: CGFloat) -> CGFloat {
            min(max(x, bounds.minX), max(bounds.minX, bounds.maxX - toolbarSize.width))
        }
        let below = selection.maxY + gap
        if below + toolbarSize.height <= bounds.maxY {
            return CGPoint(x: clampedX(selection.maxX - toolbarSize.width), y: below)
        }
        let above = selection.minY - gap - toolbarSize.height
        if above >= bounds.minY {
            return CGPoint(x: clampedX(selection.maxX - toolbarSize.width), y: above)
        }
        return CGPoint(
            x: clampedX(selection.maxX - gap - toolbarSize.width),
            y: selection.maxY - gap - toolbarSize.height
        )
    }

    /// 尺寸标签：选区左上角外侧；上方放不下就放到选区内侧。
    public static func labelOrigin(labelSize: CGSize, selection: CGRect, bounds: CGRect, gap: CGFloat = 4) -> CGPoint {
        let x = min(max(selection.minX, bounds.minX), max(bounds.minX, bounds.maxX - labelSize.width))
        let outside = selection.minY - gap - labelSize.height
        if outside >= bounds.minY {
            return CGPoint(x: x, y: outside)
        }
        return CGPoint(x: x + gap, y: selection.minY + gap)
    }
}
```

`Sources/ScreenshotModule/ImageCropper.swift`:

```swift
import CoreGraphics

public enum ImageCropper {
    /// 按选区从定格的整屏图像里裁剪。
    /// rect 是屏内坐标（左上角原点、pt）；scale 是这块屏的像素倍数（Retina 为 2）。
    /// CGImage 的像素坐标同样以左上角为原点，所以只需要乘以 scale、取整、裁到图像范围内。
    public static func crop(_ image: CGImage, rect: CGRect, scale: CGFloat) -> CGImage? {
        let pixelRect = CGRect(
            x: (rect.minX * scale).rounded(),
            y: (rect.minY * scale).rounded(),
            width: (rect.width * scale).rounded(),
            height: (rect.height * scale).rounded()
        )
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = pixelRect.intersection(imageBounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        return image.cropping(to: clipped)
    }
}
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 146 tests in 22 suites passed`，零警告。

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/ScreenshotModule Tests/ScreenshotModuleTests
git commit -m "feat(screenshot): module target with window locator, selection state machine, toolbar placement and cropper"
```

---

### Task 4: 保存与文字识别 —— 设置、文件名、保存回退、Vision OCR

**Files:**
- Create: `Sources/ScreenshotModule/ScreenshotSettings.swift`, `Sources/ScreenshotModule/ScreenshotFileNamer.swift`, `Sources/ScreenshotModule/ScreenshotSaver.swift`, `Sources/ScreenshotModule/TextRecognizer.swift`
- Test: `Tests/ScreenshotModuleTests/ScreenshotSettingsTests.swift`, `Tests/ScreenshotModuleTests/ScreenshotFileNamerTests.swift`, `Tests/ScreenshotModuleTests/ScreenshotSaverTests.swift`, `Tests/ScreenshotModuleTests/TextRecognizerTests.swift`

**Interfaces:**
- Consumes: `Core.ImageEncoding.pngData(from:pointSize:)`（Task 2）
- Produces:
  - `public struct ScreenshotSettings { static let saveFolderKey = "screenshot.saveFolder"; static var desktopURL: URL; init(defaults: UserDefaults = .standard); var saveFolder: URL { get nonmutating set } }`
  - `ScreenshotFileNamer.baseName(for: Date, timeZone: TimeZone = .current) -> String`、`fileName(for:timeZone:exists:) -> String`
  - `public enum SaveOutcome: Equatable { case saved(URL), savedToFallback(URL), failed }`
  - `public struct ScreenshotSaver { init(fallbackFolder: URL = ScreenshotSettings.desktopURL, now: @escaping () -> Date = Date.init); func save(_ image: CGImage, pointSize: CGSize, to folder: URL) -> SaveOutcome }`
  - `TextRecognizer.recognize(_ image: CGImage) async throws -> String`、`TextRecognizer.Fragment`、`TextRecognizer.orderedText(from:) -> String`

对 spec §2.5 的细化：垂直位置接近（midY 之差小于较矮者高度的一半）的文字片段算同一行，行内自左而右、用**空格**连接；行与行之间换行。

- [ ] **Step 1: 写失败的测试（四个文件）**

`Tests/ScreenshotModuleTests/ScreenshotSettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct ScreenshotSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsToDesktop() {
        let settings = ScreenshotSettings(defaults: makeDefaults())
        #expect(settings.saveFolder == ScreenshotSettings.desktopURL)
        #expect(settings.saveFolder.path.hasSuffix("/Desktop"))
    }

    @Test func storesAndReadsFolder() {
        let defaults = makeDefaults()
        ScreenshotSettings(defaults: defaults).saveFolder = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)

        #expect(ScreenshotSettings(defaults: defaults).saveFolder.path == "/tmp/shots")
        #expect(defaults.string(forKey: ScreenshotSettings.saveFolderKey) == "/tmp/shots")
    }

    @Test func emptyStoredPathFallsBackToDesktop() {
        let defaults = makeDefaults()
        defaults.set("", forKey: ScreenshotSettings.saveFolderKey)
        #expect(ScreenshotSettings(defaults: defaults).saveFolder == ScreenshotSettings.desktopURL)
    }
}
```

`Tests/ScreenshotModuleTests/ScreenshotFileNamerTests.swift`:

```swift
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct ScreenshotFileNamerTests {
    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-09-21 14:32:05 UTC
    private let date = Date(timeIntervalSince1970: 1_790_001_125)

    @Test func baseNameUsesDateAndTimeWithDots() {
        #expect(ScreenshotFileNamer.baseName(for: date, timeZone: utc) == "MyKit 2026-09-21 14.32.05")
    }

    @Test func fileNameAddsPNGExtension() {
        let name = ScreenshotFileNamer.fileName(for: date, timeZone: utc) { _ in false }
        #expect(name == "MyKit 2026-09-21 14.32.05.png")
    }

    @Test func appendsCounterWhenNameIsTaken() {
        let taken: Set<String> = ["MyKit 2026-09-21 14.32.05.png", "MyKit 2026-09-21 14.32.05 (2).png"]
        let name = ScreenshotFileNamer.fileName(for: date, timeZone: utc) { taken.contains($0) }
        #expect(name == "MyKit 2026-09-21 14.32.05 (3).png")
    }
}
```

`Tests/ScreenshotModuleTests/ScreenshotSaverTests.swift`:

```swift
import AppKit
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct ScreenshotSaverTests {
    private let date = Date(timeIntervalSince1970: 1_790_001_125)

    private func makeImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        return try #require(context.makeImage())
    }

    /// 每个测试用自己的临时目录，绝不碰真实的桌面。
    private func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mykit-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func savesPNGIntoFolder() throws {
        let folder = try makeTempFolder()
        let fallback = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: fallback) }
        let saver = ScreenshotSaver(fallbackFolder: fallback, now: { self.date })

        let outcome = saver.save(try makeImage(), pointSize: CGSize(width: 20, height: 10), to: folder)

        guard case .saved(let url) = outcome else {
            Issue.record("expected .saved, got \(outcome)")
            return
        }
        #expect(url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(url.lastPathComponent.hasPrefix("MyKit "))
        #expect(url.pathExtension == "png")
        let decoded = try #require(NSBitmapImageRep(data: try Data(contentsOf: url)))
        #expect(decoded.pixelsWide == 40)
        #expect(decoded.pixelsHigh == 20)
    }

    @Test func secondSaveInSameSecondGetsCounterSuffix() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let saver = ScreenshotSaver(fallbackFolder: folder, now: { self.date })
        let image = try makeImage()

        let first = saver.save(image, pointSize: CGSize(width: 20, height: 10), to: folder)
        let second = saver.save(image, pointSize: CGSize(width: 20, height: 10), to: folder)

        guard case .saved(let firstURL) = first, case .saved(let secondURL) = second else {
            Issue.record("expected both saves to succeed")
            return
        }
        #expect(firstURL != secondURL)
        #expect(secondURL.lastPathComponent.hasSuffix(" (2).png"))
    }

    @Test func fallsBackWhenFolderDoesNotExist() throws {
        let fallback = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: fallback) }
        let missing = fallback.appendingPathComponent("deleted-by-user")
        let saver = ScreenshotSaver(fallbackFolder: fallback, now: { self.date })

        let outcome = saver.save(try makeImage(), pointSize: CGSize(width: 20, height: 10), to: missing)

        guard case .savedToFallback(let url) = outcome else {
            Issue.record("expected .savedToFallback, got \(outcome)")
            return
        }
        #expect(url.deletingLastPathComponent().standardizedFileURL == fallback.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: missing.path))     // 不会自动创建被删掉的文件夹
    }

    @Test func failsWhenFallbackIsAlsoUnavailable() throws {
        let root = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let saver = ScreenshotSaver(fallbackFolder: root.appendingPathComponent("no-fallback"), now: { self.date })

        let outcome = saver.save(try makeImage(), pointSize: CGSize(width: 20, height: 10), to: root.appendingPathComponent("no-folder"))

        #expect(outcome == .failed)
    }

    @Test func failsWithoutRetryWhenFolderIsTheFallbackItself() throws {
        let root = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("gone")
        let saver = ScreenshotSaver(fallbackFolder: missing, now: { self.date })

        #expect(saver.save(try makeImage(), pointSize: CGSize(width: 20, height: 10), to: missing) == .failed)
    }
}
```

`Tests/ScreenshotModuleTests/TextRecognizerTests.swift`:

```swift
import AppKit
import Testing
@testable import ScreenshotModule

@Suite struct TextRecognizerTests {
    /// 在白底上用黑字画几行文字，生成一张 2× 的测试图片。不需要屏幕录制授权。
    private func makeImage(lines: [String]) throws -> CGImage {
        let width = 1400, height = 120 * max(lines.count, 1) + 80
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 56),
            .foregroundColor: NSColor.black,
        ]
        for (index, line) in lines.enumerated() {
            // AppKit 坐标 y 向上：第一行画在最上面
            let y = CGFloat(height) - 100 - CGFloat(index) * 120
            (line as NSString).draw(at: NSPoint(x: 40, y: y), withAttributes: attributes)
        }
        return try #require(rep.cgImage)
    }

    @Test func recognisesChineseAndEnglishInReadingOrder() async throws {
        let image = try makeImage(lines: ["MyKit 截图文字识别测试", "Hello OCR 2026"])

        let text = try await TextRecognizer.recognize(image)

        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines.first?.contains("文字识别") == true)
        #expect(lines.last?.contains("Hello") == true)
        #expect(lines.last?.contains("2026") == true)
    }

    @Test func blankImageGivesEmptyString() async throws {
        let text = try await TextRecognizer.recognize(try makeImage(lines: []))
        #expect(text == "")
    }

    // MARK: 排序（纯逻辑）

    private func fragment(_ text: String, x: CGFloat, y: CGFloat) -> TextRecognizer.Fragment {
        TextRecognizer.Fragment(text: text, box: CGRect(x: x, y: y, width: 0.2, height: 0.05))
    }

    @Test func ordersRowsTopToBottom() {
        // Vision 坐标 y 向上：y 越大越靠上
        let text = TextRecognizer.orderedText(from: [
            fragment("第三行", x: 0.1, y: 0.2),
            fragment("第一行", x: 0.1, y: 0.8),
            fragment("第二行", x: 0.1, y: 0.5),
        ])
        #expect(text == "第一行\n第二行\n第三行")
    }

    @Test func fragmentsOnTheSameRowGoLeftToRightJoinedBySpace() {
        let text = TextRecognizer.orderedText(from: [
            fragment("右", x: 0.6, y: 0.805),
            fragment("左", x: 0.1, y: 0.80),
            fragment("下一行", x: 0.1, y: 0.6),
        ])
        #expect(text == "左 右\n下一行")
    }

    @Test func noFragmentsGiveEmptyString() {
        #expect(TextRecognizer.orderedText(from: []) == "")
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'ScreenshotSettings' in scope` 等。

- [ ] **Step 3: 写实现（四个文件）**

`Sources/ScreenshotModule/ScreenshotSettings.swift`:

```swift
import Foundation

public struct ScreenshotSettings {
    public static let saveFolderKey = "screenshot.saveFolder"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public static var desktopURL: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// 截图保存到哪个文件夹。未设置时为桌面。
    public var saveFolder: URL {
        get {
            guard let path = defaults.string(forKey: Self.saveFolderKey), !path.isEmpty else {
                return Self.desktopURL
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        nonmutating set {
            defaults.set(newValue.path, forKey: Self.saveFolderKey)
        }
    }
}
```

`Sources/ScreenshotModule/ScreenshotFileNamer.swift`:

```swift
import Foundation

public enum ScreenshotFileNamer {
    /// 形如 "MyKit 2026-09-21 14.32.05"（不含扩展名）。
    public static func baseName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "MyKit " + formatter.string(from: date)
    }

    /// 形如 "MyKit 2026-09-21 14.32.05.png"；同名已存在则依次尝试 " (2)"、" (3)"……
    /// exists 由调用方提供（传入文件名，返回该文件是否已存在）。
    public static func fileName(for date: Date, timeZone: TimeZone = .current, exists: (String) -> Bool) -> String {
        let base = baseName(for: date, timeZone: timeZone)
        var candidate = base + ".png"
        var counter = 2
        while exists(candidate) {
            candidate = "\(base) (\(counter)).png"
            counter += 1
        }
        return candidate
    }
}
```

`Sources/ScreenshotModule/ScreenshotSaver.swift`:

```swift
import Core
import CoreGraphics
import Foundation

public enum SaveOutcome: Equatable {
    case saved(URL)
    /// 指定文件夹写不进去，已改存到后备文件夹（桌面）
    case savedToFallback(URL)
    case failed
}

public struct ScreenshotSaver {
    private let fallbackFolder: URL
    private let now: () -> Date

    /// fallbackFolder 默认是桌面；测试里传临时目录，避免往真实桌面写文件。
    public init(fallbackFolder: URL = ScreenshotSettings.desktopURL, now: @escaping () -> Date = Date.init) {
        self.fallbackFolder = fallbackFolder
        self.now = now
    }

    public func save(_ image: CGImage, pointSize: CGSize, to folder: URL) -> SaveOutcome {
        guard let data = ImageEncoding.pngData(from: image, pointSize: pointSize) else { return .failed }
        if let url = write(data, into: folder) {
            return .saved(url)
        }
        if folder.standardizedFileURL != fallbackFolder.standardizedFileURL,
           let url = write(data, into: fallbackFolder) {
            return .savedToFallback(url)
        }
        return .failed
    }

    /// 文件夹不存在时不会自动创建（那通常意味着用户把它删了或移走了），直接算失败。
    private func write(_ data: Data, into folder: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        let name = ScreenshotFileNamer.fileName(for: now()) { candidate in
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path)
        }
        let url = folder.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
```

`Sources/ScreenshotModule/TextRecognizer.swift`:

```swift
import CoreGraphics
import Foundation
import Vision

/// 文字识别（OCR）。用系统自带的 Vision，离线，支持简体中文、繁体中文、英文。
public enum TextRecognizer {
    /// 识别出的一段文字及其位置。box 是 Vision 的归一化坐标：0…1，**左下角为原点**。
    public struct Fragment: Equatable {
        public let text: String
        public let box: CGRect

        public init(text: String, box: CGRect) {
            self.text = text
            self.box = box
        }
    }

    /// 识别图片里的文字。没有文字时返回空字符串。识别在后台线程执行。
    public static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let fragments = (request.results ?? []).compactMap { observation -> Fragment? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return Fragment(text: candidate.string, box: observation.boundingBox)
            }
            return orderedText(from: fragments)
        }.value
    }

    /// 按阅读顺序拼成文本：自上而下分行；垂直位置接近的片段算同一行，行内自左而右、用空格连接；行与行之间换行。
    public static func orderedText(from fragments: [Fragment]) -> String {
        let sorted = fragments.sorted { $0.box.midY > $1.box.midY }     // Vision 的 y 向上，midY 大的在上面
        var rows: [[Fragment]] = []
        for fragment in sorted {
            if let reference = rows.last?.first,
               abs(reference.box.midY - fragment.box.midY) < min(reference.box.height, fragment.box.height) / 2 {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows
            .map { row in row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 162 tests in 26 suites passed`，零警告。第一次运行时 `TextRecognizerTests` 可能要 20 多秒（Vision 加载模型），再跑一次约 0.3 秒。

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenshotModule Tests/ScreenshotModuleTests
git commit -m "feat(screenshot): save settings, file naming, saver with desktop fallback, Vision text recognizer"
```

---

### Task 5: 截屏与遮罩 —— ScreenCaptureKit 定格、遮罩面板、选区绘制、工具条

**Files:**
- Create: `Sources/ScreenshotModule/CaptureAction.swift`, `Sources/ScreenshotModule/DisplaySnapshot.swift`, `Sources/ScreenshotModule/ScreenCapturer.swift`, `Sources/ScreenshotModule/CaptureToolbar.swift`, `Sources/ScreenshotModule/OverlayView.swift`, `Sources/ScreenshotModule/CaptureOverlayController.swift`
- Test: `Tests/ScreenshotModuleTests/OverlayKeyMapTests.swift`, `Tests/ScreenshotModuleTests/CaptureResultTests.swift`

**Interfaces:**
- Consumes: `SelectionModel`、`WindowLocator`、`ToolbarPlacement`、`ImageCropper`、`ScreenGeometry`（Task 3）
- Produces:
  - `public enum CaptureAction: Equatable, CaseIterable { case pin, recognize, save, copy }`
  - `enum OverlayCommand: Equatable { case cancel; case perform(CaptureAction) }`、`OverlayKeyMap.command(keyCode:characters:modifiers:) -> OverlayCommand?`
  - `public struct ScreenDescriptor: Equatable, Sendable { displayID, frame（AppKit 全局）, cgBounds（CG 全局）, scale }`
  - `public struct DisplaySnapshot: @unchecked Sendable { screen: ScreenDescriptor; image: CGImage; localBounds; imageScale }`
  - `public struct CaptureResult { image: CGImage; pointSize: CGSize; screenRect: CGRect（AppKit 全局）; static func make(selection:snapshot:) -> CaptureResult? }`
  - `ScreenCapturer.currentScreens() -> [ScreenDescriptor]`（`@MainActor`）、`ScreenCapturer.captureAll(screens:) async throws -> [DisplaySnapshot]`
  - `@MainActor final class CaptureOverlayController { init(snapshots: [DisplaySnapshot], cgWindows: [CGRect]); var onFinish: ((CaptureAction, CaptureResult) -> Void)?; var onEnd: (() -> Void)?; func begin(); func end() }`

要点：
- 定格画面放在 `NSImageView` 里，`OverlayView` 透明地盖在上面，只画暗层（用 even-odd 路径把高亮区域挖空）、边框、手柄和尺寸标签 —— 鼠标移动时不需要重画整屏图像。
- `OverlayPanel` 与剪切板的 `FloatingPanel` 同一个思路：`.nonactivatingPanel` + `canBecomeKey = true`，键盘可用但 MyKit 不会变成前台 App。level 用 `CGShieldingWindowLevel()`，盖过菜单栏和 Dock。
- 多显示器：每块屏一个面板；一块屏上开始操作时，其余屏的选区清掉；键盘指令由控制器统一处理（作用于有选区的那块屏）。
- `end()` 时把面板的 `contentView` 置空并清空数组，定格画面立即释放。

这一任务里能自动测试的是键盘映射和成品计算；面板、绘制、鼠标交互在 Task 7 手动验收。

- [ ] **Step 1: 写失败的测试（两个文件）**

`Tests/ScreenshotModuleTests/OverlayKeyMapTests.swift`:

```swift
import AppKit
import Testing
@testable import ScreenshotModule

@Suite struct OverlayKeyMapTests {
    @Test func escapeCancelsRegardlessOfModifiers() {
        #expect(OverlayKeyMap.command(keyCode: 53, characters: "\u{1b}", modifiers: []) == .cancel)
        #expect(OverlayKeyMap.command(keyCode: 53, characters: "\u{1b}", modifiers: [.shift]) == .cancel)
    }

    @Test func returnAndKeypadEnterCopy() {
        #expect(OverlayKeyMap.command(keyCode: 36, characters: "\r", modifiers: []) == .perform(.copy))
        #expect(OverlayKeyMap.command(keyCode: 76, characters: "\u{03}", modifiers: [.numericPad]) == .perform(.copy))
    }

    @Test func commandLettersMapToActions() {
        #expect(OverlayKeyMap.command(keyCode: 8, characters: "c", modifiers: [.command]) == .perform(.copy))
        #expect(OverlayKeyMap.command(keyCode: 1, characters: "s", modifiers: [.command]) == .perform(.save))
        #expect(OverlayKeyMap.command(keyCode: 15, characters: "r", modifiers: [.command]) == .perform(.recognize))
        #expect(OverlayKeyMap.command(keyCode: 17, characters: "t", modifiers: [.command]) == .perform(.pin))
    }

    @Test func capsLockDoesNotBreakShortcuts() {
        #expect(OverlayKeyMap.command(keyCode: 1, characters: "S", modifiers: [.command, .capsLock]) == .perform(.save))
    }

    @Test func lettersWithoutCommandOrWithExtraModifiersDoNothing() {
        #expect(OverlayKeyMap.command(keyCode: 1, characters: "s", modifiers: []) == nil)
        #expect(OverlayKeyMap.command(keyCode: 1, characters: "s", modifiers: [.command, .shift]) == nil)
        #expect(OverlayKeyMap.command(keyCode: 36, characters: "\r", modifiers: [.command]) == nil)
        #expect(OverlayKeyMap.command(keyCode: 0, characters: "a", modifiers: [.command]) == nil)
    }
}
```

`Tests/ScreenshotModuleTests/CaptureResultTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct CaptureResultTests {
    /// 一块 100×50 pt 的 2× 屏（图像 200×100 像素），位于主屏右侧。
    private func makeSnapshot() throws -> DisplaySnapshot {
        let context = try #require(CGContext(
            data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let screen = ScreenDescriptor(
            displayID: 7,
            frame: CGRect(x: 1600, y: 0, width: 100, height: 50),
            cgBounds: CGRect(x: 1600, y: 950, width: 100, height: 50),
            scale: 2
        )
        return DisplaySnapshot(screen: screen, image: image)
    }

    @Test func snapshotExposesLocalBoundsAndImageScale() throws {
        let snapshot = try makeSnapshot()
        #expect(snapshot.localBounds == CGRect(x: 0, y: 0, width: 100, height: 50))
        #expect(snapshot.imageScale == 2)
    }

    @Test func resultIsCroppedInPixelsAndPositionedInAppKitCoordinates() throws {
        let result = try #require(CaptureResult.make(
            selection: CGRect(x: 10, y: 5, width: 40, height: 20), snapshot: try makeSnapshot()
        ))

        #expect(result.image.width == 80)
        #expect(result.image.height == 40)
        #expect(result.pointSize == CGSize(width: 40, height: 20))
        #expect(result.screenRect == CGRect(x: 1610, y: 25, width: 40, height: 20))     // y = 50 - (5 + 20)
    }

    @Test func emptySelectionGivesNoResult() throws {
        #expect(CaptureResult.make(selection: .zero, snapshot: try makeSnapshot()) == nil)
    }

    @Test func pixelSizeMultipliesPointSizeByScale() {
        let size = ScreenCapturer.pixelSize(pointSize: CGSize(width: 1512, height: 982), scale: 2)
        #expect(size.width == 3024)
        #expect(size.height == 1964)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'OverlayKeyMap' in scope` 等。

- [ ] **Step 3: 写数据类型与截屏（三个文件）**

`Sources/ScreenshotModule/CaptureAction.swift`:

```swift
import AppKit

/// 选好区域之后可以做的四件事。
public enum CaptureAction: Equatable, CaseIterable {
    case pin, recognize, save, copy
}

/// 遮罩上的一次"指令"：来自键盘、工具条按钮、右键或双击。
enum OverlayCommand: Equatable {
    case cancel
    case perform(CaptureAction)
}

/// 键盘 → 指令。纯函数。
enum OverlayKeyMap {
    static func command(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) -> OverlayCommand? {
        let relevant = modifiers.intersection([.command, .option, .control, .shift])
        if keyCode == 53 { return .cancel }                                   // Esc
        if relevant.isEmpty, keyCode == 36 || keyCode == 76 {                 // 回车 / 小键盘回车
            return .perform(.copy)
        }
        guard relevant == .command, let key = characters?.lowercased() else { return nil }
        switch key {
        case "c": return .perform(.copy)
        case "s": return .perform(.save)
        case "r": return .perform(.recognize)
        case "t": return .perform(.pin)
        default: return nil
        }
    }
}
```

`Sources/ScreenshotModule/DisplaySnapshot.swift`:

```swift
import CoreGraphics

/// 一块显示器的描述（在主线程从 NSScreen 读出，之后可以带到后台线程用）。
public struct ScreenDescriptor: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    /// AppKit 全局坐标（主屏左下角为原点、y 向上），即 NSScreen.frame
    public let frame: CGRect
    /// CG 全局坐标（主屏左上角为原点、y 向下），即 CGDisplayBounds
    public let cgBounds: CGRect
    /// 像素倍数，Retina 为 2
    public let scale: CGFloat

    public init(displayID: CGDirectDisplayID, frame: CGRect, cgBounds: CGRect, scale: CGFloat) {
        self.displayID = displayID
        self.frame = frame
        self.cgBounds = cgBounds
        self.scale = scale
    }
}

/// 一块显示器的定格画面。CGImage 创建后不可变，跨线程传递是安全的。
public struct DisplaySnapshot: @unchecked Sendable {
    public let screen: ScreenDescriptor
    public let image: CGImage

    public init(screen: ScreenDescriptor, image: CGImage) {
        self.screen = screen
        self.image = image
    }

    /// 这块屏的屏内坐标范围：(0, 0, 宽, 高)，单位 pt
    public var localBounds: CGRect {
        CGRect(origin: .zero, size: screen.frame.size)
    }

    /// 图像像素与 pt 的实际比例（以图像为准，比 screen.scale 更可靠）
    public var imageScale: CGFloat {
        screen.frame.width > 0 ? CGFloat(image.width) / screen.frame.width : screen.scale
    }
}

/// 一次截图的成品。
public struct CaptureResult {
    public let image: CGImage
    /// 图片的 pt 尺寸（= 选区大小）
    public let pointSize: CGSize
    /// 选区在屏幕上的位置，AppKit 全局坐标 —— 贴图窗口直接用它当 frame
    public let screenRect: CGRect

    /// 按选区（屏内坐标）从定格画面裁出成品。选区无效时返回 nil。
    public static func make(selection: CGRect, snapshot: DisplaySnapshot) -> CaptureResult? {
        guard let image = ImageCropper.crop(snapshot.image, rect: selection, scale: snapshot.imageScale) else { return nil }
        return CaptureResult(
            image: image,
            pointSize: selection.size,
            screenRect: ScreenGeometry.appKitRect(fromLocal: selection, screenFrame: snapshot.screen.frame)
        )
    }
}
```

`Sources/ScreenshotModule/ScreenCapturer.swift`:

```swift
import AppKit
import ScreenCaptureKit

/// 用 ScreenCaptureKit 把每块显示器各定格成一张图。需要"屏幕录制"授权。
public enum ScreenCapturer {
    public enum CaptureError: Error {
        case noDisplayCaptured
    }

    @MainActor
    public static func currentScreens() -> [ScreenDescriptor] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            return ScreenDescriptor(
                displayID: displayID,
                frame: screen.frame,
                cgBounds: CGDisplayBounds(displayID),
                scale: screen.backingScaleFactor
            )
        }
    }

    /// 截图的像素尺寸 = pt 尺寸 × 倍数。
    static func pixelSize(pointSize: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        (Int((pointSize.width * scale).rounded()), Int((pointSize.height * scale).rounded()))
    }

    /// 并发截取所有显示器。某一块失败就跳过；全部失败才抛错。
    public static func captureAll(screens: [ScreenDescriptor]) async throws -> [DisplaySnapshot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let snapshots = await withTaskGroup(of: DisplaySnapshot?.self) { group in
            for screen in screens {
                guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { continue }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let configuration = SCStreamConfiguration()
                let size = pixelSize(pointSize: screen.frame.size, scale: screen.scale)
                configuration.width = size.width
                configuration.height = size.height
                configuration.showsCursor = false
                group.addTask {
                    guard let image = try? await SCScreenshotManager.captureImage(
                        contentFilter: filter, configuration: configuration
                    ) else { return nil }
                    return DisplaySnapshot(screen: screen, image: image)
                }
            }
            var collected: [DisplaySnapshot] = []
            for await snapshot in group {
                if let snapshot { collected.append(snapshot) }
            }
            return collected
        }
        guard !snapshots.isEmpty else { throw CaptureError.noDisplayCaptured }
        return snapshots
    }
}
```

- [ ] **Step 4: 写遮罩界面（三个文件）**

`Sources/ScreenshotModule/CaptureToolbar.swift`:

```swift
import AppKit

/// 选区旁边的工具条：贴图 / 识别文字 / 保存 / 复制 / 取消。
final class CaptureToolbar: NSVisualEffectView {
    var onCommand: ((OverlayCommand) -> Void)?

    private let items: [(title: String, symbol: String, hint: String, command: OverlayCommand)] = [
        ("贴图", "pin", "贴在屏幕上  ⌘T", .perform(.pin)),
        ("识别文字", "text.viewfinder", "识别图中文字  ⌘R", .perform(.recognize)),
        ("保存", "square.and.arrow.down", "保存为 PNG 文件  ⌘S", .perform(.save)),
        ("复制", "doc.on.doc", "复制到剪切板  ↩", .perform(.copy)),
        ("", "xmark", "取消  Esc", .cancel),
    ]

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        state = .active
        blendingMode = .withinWindow
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        let buttons = items.enumerated().map { index, item -> NSButton in
            let image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.hint) ?? NSImage()
            let button = NSButton(title: item.title, image: image, target: self, action: #selector(buttonClicked(_:)))
            button.tag = index
            button.bezelStyle = .accessoryBarAction
            button.imagePosition = item.title.isEmpty ? .imageOnly : .imageLeading
            button.toolTip = item.hint
            return button
        }
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let size = stack.fittingSize
        setFrameSize(size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func buttonClicked(_ sender: NSButton) {
        guard items.indices.contains(sender.tag) else { return }
        onCommand?(items[sender.tag].command)
    }
}
```

`Sources/ScreenshotModule/OverlayView.swift`:

```swift
import AppKit

@MainActor
protocol OverlayViewDelegate: AnyObject {
    /// 用户开始在这块屏上操作（其他屏的选区要清掉）
    func overlayViewDidBeginInteraction(_ view: OverlayView)
    func overlayView(_ view: OverlayView, didRequest command: OverlayCommand)
}

/// 盖在定格画面上面的那一层：画暗层、高亮 / 选区、手柄、尺寸标签，并把鼠标事件交给 SelectionModel。
/// isFlipped = true，所以视图坐标就是"屏内坐标"（左上角原点）。
final class OverlayView: NSView {
    weak var delegate: OverlayViewDelegate?
    private(set) var model: SelectionModel
    private let toolbar = CaptureToolbar()

    private static let handleSide: CGFloat = 8
    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    init(frame: NSRect, windows: [CGRect]) {
        model = SelectionModel(bounds: CGRect(origin: .zero, size: frame.size), windows: windows)
        super.init(frame: frame)
        toolbar.isHidden = true
        toolbar.onCommand = { [weak self] command in
            guard let self else { return }
            self.delegate?.overlayView(self, didRequest: command)
        }
        addSubview(toolbar)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Esc / 右键的第一级：清掉这块屏上的选区。返回 true 表示这里本来就没有东西可清。
    func cancelSelection() -> Bool {
        let nothingToCancel = model.cancel()
        refresh()
        return nothingToCancel
    }

    func resetSelection() {
        model.reset()
        refresh()
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        if let highlight = model.highlight {
            dim.appendRect(highlight)
            dim.windingRule = .evenOdd          // 高亮区域挖空，露出下面未变暗的定格画面
        }
        NSColor.black.withAlphaComponent(0.45).setFill()
        dim.fill()

        guard let highlight = model.highlight else { return }
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: highlight.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = model.selection == nil ? 2 : 1
        border.stroke()

        guard let selection = model.selection else { return }
        if model.hasConfirmedSelection {
            for (_, point) in SelectionModel.handlePoints(for: selection) {
                let side = Self.handleSide
                let square = NSBezierPath(rect: CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side))
                NSColor.white.setFill()
                square.fill()
                NSColor.controlAccentColor.setStroke()
                square.stroke()
            }
        }
        drawSizeLabel(for: selection)
    }

    private func drawSizeLabel(for selection: CGRect) {
        let text = "\(Int(selection.width)) × \(Int(selection.height))" as NSString
        let textSize = text.size(withAttributes: Self.labelAttributes)
        let labelSize = CGSize(width: textSize.width + 12, height: textSize.height + 6)
        let origin = ToolbarPlacement.labelOrigin(labelSize: labelSize, selection: selection, bounds: bounds)
        let background = NSBezierPath(roundedRect: CGRect(origin: origin, size: labelSize), xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        background.fill()
        text.draw(at: CGPoint(x: origin.x + 6, y: origin.y + 3), withAttributes: Self.labelAttributes)
    }

    private func refresh() {
        if model.hasConfirmedSelection, !model.isAdjusting, let selection = model.selection {
            toolbar.setFrameOrigin(ToolbarPlacement.toolbarOrigin(
                toolbarSize: toolbar.frame.size, selection: selection, bounds: bounds
            ))
            toolbar.isHidden = false
        } else {
            toolbar.isHidden = true
        }
        needsDisplay = true
    }

    // MARK: 鼠标

    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = location(of: event)
        let before = model.highlight
        model.mouseMoved(to: point)
        updateCursor(at: point)
        if model.highlight != before { needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        // 鼠标移到了另一块屏：这块屏上的窗口高亮要熄掉（已有选区时 mouseMoved 本来就不起作用）
        let before = model.highlight
        model.mouseMoved(to: CGPoint(x: -1, y: -1))
        if model.highlight != before { needsDisplay = true }
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: location(of: event))
    }

    override func mouseDown(with event: NSEvent) {
        let point = location(of: event)
        window?.makeKey()
        delegate?.overlayViewDidBeginInteraction(self)
        if event.clickCount == 2, model.hasConfirmedSelection, model.selection?.contains(point) == true {
            delegate?.overlayView(self, didRequest: .perform(.copy))      // 双击选区 = 复制
            return
        }
        model.mouseDown(at: point)
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        model.mouseDragged(to: location(of: event))
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        let point = location(of: event)
        model.mouseUp(at: point)
        updateCursor(at: point)
        refresh()
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.overlayView(self, didRequest: .cancel)
    }

    private func updateCursor(at point: CGPoint) {
        if !toolbar.isHidden, toolbar.frame.contains(point) {
            NSCursor.arrow.set()                   // 工具条上用普通箭头
            return
        }
        if let handle = model.handle(at: point) {
            switch handle {
            case .left, .right: NSCursor.resizeLeftRight.set()
            case .top, .bottom: NSCursor.resizeUpDown.set()
            case .topLeft, .topRight, .bottomLeft, .bottomRight: NSCursor.crosshair.set()
            }
        } else if model.hasConfirmedSelection, model.selection?.contains(point) == true {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }
}
```

`Sources/ScreenshotModule/CaptureOverlayController.swift`:

```swift
import AppKit

/// 盖住整块屏幕的面板。和剪切板面板一样：能接收键盘，但不会让 MyKit 变成前台 App。
final class OverlayPanel: NSPanel {
    /// 返回 true 表示已处理
    var keyHandler: ((NSEvent) -> Bool)?

    init(screenFrame: CGRect) {
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))     // 盖过菜单栏和 Dock
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        setFrame(screenFrame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            _ = keyHandler?(event)
            return                       // 截图期间所有按键到此为止（也避免系统"咚"一声）
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        _ = keyHandler?(event)
        return true                      // ⌘ 组合键同样不再往下传
    }
}

/// 一次截图会话：每块屏一个遮罩面板；选好并执行某个操作、或取消后结束。
@MainActor
final class CaptureOverlayController: OverlayViewDelegate {
    /// 用户选好区域并选择了一个操作。调用时遮罩已经关闭。
    var onFinish: ((CaptureAction, CaptureResult) -> Void)?
    /// 会话结束（无论是完成还是取消）时一定会调用一次。
    var onEnd: (() -> Void)?

    private struct Entry {
        let snapshot: DisplaySnapshot
        let panel: OverlayPanel
        let view: OverlayView
    }

    private var entries: [Entry] = []
    private var hasEnded = false

    /// cgWindows：截图那一刻屏幕上的窗口边框（CG 全局坐标，前 → 后）
    init(snapshots: [DisplaySnapshot], cgWindows: [CGRect]) {
        entries = snapshots.map { snapshot in
            let panel = OverlayPanel(screenFrame: snapshot.screen.frame)
            let localBounds = snapshot.localBounds

            let imageView = NSImageView(frame: localBounds)
            imageView.image = NSImage(cgImage: snapshot.image, size: localBounds.size)
            imageView.imageScaling = .scaleAxesIndependently
            imageView.imageFrameStyle = .none
            imageView.autoresizingMask = [.width, .height]

            let windows = WindowLocator.localRects(cgWindows: cgWindows, displayBounds: snapshot.screen.cgBounds)
            let overlay = OverlayView(frame: localBounds, windows: windows)
            overlay.autoresizingMask = [.width, .height]

            let container = NSView(frame: localBounds)
            container.addSubview(imageView)
            container.addSubview(overlay)
            panel.contentView = container
            return Entry(snapshot: snapshot, panel: panel, view: overlay)
        }
        for entry in entries {
            entry.view.delegate = self
            entry.panel.keyHandler = { [weak self] event in
                self?.handleKey(event) ?? false
            }
        }
    }

    func begin() {
        let mouse = NSEvent.mouseLocation
        for entry in entries {
            entry.panel.orderFrontRegardless()
        }
        let underMouse = entries.first { NSMouseInRect(mouse, $0.snapshot.screen.frame, false) } ?? entries.first
        underMouse?.panel.makeKey()
        underMouse?.panel.makeFirstResponder(underMouse?.view)
        NSCursor.crosshair.set()
    }

    func end() {
        guard !hasEnded else { return }
        hasEnded = true
        for entry in entries {
            entry.panel.keyHandler = nil
            entry.panel.contentView = nil      // 立刻释放定格画面
            entry.panel.close()
        }
        entries.removeAll()
        NSCursor.arrow.set()
        onEnd?()
    }

    // MARK: OverlayViewDelegate

    func overlayViewDidBeginInteraction(_ view: OverlayView) {
        for entry in entries where entry.view !== view {
            entry.view.resetSelection()        // 同一时间只有一块屏上有选区
        }
    }

    func overlayView(_ view: OverlayView, didRequest command: OverlayCommand) {
        handle(command)
    }

    // MARK: 指令

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              let command = OverlayKeyMap.command(
                  keyCode: event.keyCode,
                  characters: event.charactersIgnoringModifiers,
                  modifiers: event.modifierFlags
              )
        else { return false }
        handle(command)
        return true
    }

    private func handle(_ command: OverlayCommand) {
        switch command {
        case .cancel:
            // 第一级：清掉选区；没有任何选区可清 → 退出截图
            var clearedSomething = false
            for entry in entries where !entry.view.cancelSelection() {
                clearedSomething = true
            }
            if !clearedSomething { end() }

        case .perform(let action):
            guard let entry = entries.first(where: { $0.view.model.hasConfirmedSelection }),
                  let selection = entry.view.model.selection,
                  let result = CaptureResult.make(selection: selection, snapshot: entry.snapshot)
            else { return }                     // 还没有选区：按键无效果
            end()
            onFinish?(action, result)
        }
    }
}
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 171 tests in 28 suites passed`，零警告。

- [ ] **Step 6: Commit**

```bash
git add Sources/ScreenshotModule Tests/ScreenshotModuleTests
git commit -m "feat(screenshot): ScreenCaptureKit capture, overlay panels with selection drawing and toolbar"
```

---

### Task 6: 贴图、识别结果窗口、操作执行

**Files:**
- Create: `Sources/ScreenshotModule/PinZoom.swift`, `Sources/ScreenshotModule/PinWindow.swift`, `Sources/ScreenshotModule/PinManager.swift`, `Sources/ScreenshotModule/OCRResultModel.swift`, `Sources/ScreenshotModule/OCRResultWindowController.swift`, `Sources/ScreenshotModule/ScreenshotActions.swift`
- Test: `Tests/ScreenshotModuleTests/PinZoomTests.swift`, `Tests/ScreenshotModuleTests/OCRResultModelTests.swift`, `Tests/ScreenshotModuleTests/ScreenshotActionsTests.swift`

**Interfaces:**
- Consumes: `CaptureAction`（Task 5）；`ScreenshotSettings`、`ScreenshotSaver`、`SaveOutcome`、`TextRecognizer`（Task 4）；`Core.PasteService.writeFromMyKit`、`PasteService.write(image:pointSize:)`、`Core.Toast`（Task 2）
- Produces:
  - `PinZoom.range = 0.1...5.0`、`PinZoom.scale(current:scrollDeltaY:) -> CGFloat`、`PinZoom.frame(current:baseSize:scale:) -> CGRect`
  - `@MainActor final class PinManager { var onImageAction: ((CaptureAction, CGImage, CGSize) -> Void)?; var count: Int; func pin(image: CGImage, at screenRect: CGRect); func closeAll() }`
  - `@MainActor final class OCRResultModel: ObservableObject { init(recognize:copy:); var text; status; isRecognizing; func run(on: CGImage) async; func copyCurrentText() }`
  - `@MainActor final class OCRResultWindowController { func recognize(_ image: CGImage) }`
  - `@MainActor final class ScreenshotActions { let pins: PinManager; init(settings: ScreenshotSettings, saver: ScreenshotSaver = ScreenshotSaver()); func perform(_ action: CaptureAction, image: CGImage, pointSize: CGSize, screenRect: CGRect?); static func message(for: SaveOutcome) -> String }`

要点：
- 贴图窗口 `canBecomeKey = false`、不激活 App；拖动用 `window.performDrag(with:)`（这样同一个 `mouseDown` 里还能识别双击关闭）；右键菜单通过 `menu(for:)` 提供。
- 识别结果窗口的状态放在 `ObservableObject` 里（不能用 `@State`）。识别与复制通过闭包注入 `OCRResultModel`，测试里用假实现。

- [ ] **Step 1: 写失败的测试（三个文件）**

`Tests/ScreenshotModuleTests/PinZoomTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct PinZoomTests {
    @Test func scrollingUpZoomsInAndDownZoomsOut() {
        #expect(PinZoom.scale(current: 1, scrollDeltaY: 10) == 1.1)
        #expect(PinZoom.scale(current: 1, scrollDeltaY: -10) == 0.9)
        #expect(PinZoom.scale(current: 2, scrollDeltaY: 0) == 2)
    }

    @Test func scaleIsClampedBetweenTenAndFiveHundredPercent() {
        #expect(PinZoom.scale(current: 4.9, scrollDeltaY: 50) == 5)
        #expect(PinZoom.scale(current: 0.11, scrollDeltaY: -50) == 0.1)
        #expect(PinZoom.scale(current: 1, scrollDeltaY: -500) == 0.1)
    }

    @Test func frameScalesAroundItsCenter() {
        let current = CGRect(x: 100, y: 200, width: 400, height: 200)      // 中心 (300, 300)
        let frame = PinZoom.frame(current: current, baseSize: CGSize(width: 400, height: 200), scale: 2)

        #expect(frame == CGRect(x: -100, y: 100, width: 800, height: 400))
        #expect(frame.midX == 300)
        #expect(frame.midY == 300)
    }

    @Test func frameUsesBaseSizeNotCurrentSize() {
        // 已经放大到 2× 的窗口再设回 1×，应当回到原始大小，而不是在当前大小上继续乘
        let current = CGRect(x: -100, y: 100, width: 800, height: 400)
        let frame = PinZoom.frame(current: current, baseSize: CGSize(width: 400, height: 200), scale: 1)
        #expect(frame == CGRect(x: 100, y: 200, width: 400, height: 200))
    }
}
```

`Tests/ScreenshotModuleTests/OCRResultModelTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@MainActor
@Suite struct OCRResultModelTests {
    private final class CopyLog {
        var values: [String] = []
    }

    private struct Boom: LocalizedError {
        var errorDescription: String? { "图片无法处理" }
    }

    private func makeImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try #require(context.makeImage())
    }

    @Test func successFillsTextCopiesItAndReportsCopied() async throws {
        let log = CopyLog()
        let model = OCRResultModel(recognize: { _ in "第一行\n第二行" }, copy: { log.values.append($0) })

        await model.run(on: try makeImage())

        #expect(model.text == "第一行\n第二行")
        #expect(model.status == "✓ 已复制全文")
        #expect(!model.isRecognizing)
        #expect(log.values == ["第一行\n第二行"])
    }

    @Test func emptyResultDoesNotTouchClipboard() async throws {
        let log = CopyLog()
        let model = OCRResultModel(recognize: { _ in "" }, copy: { log.values.append($0) })

        await model.run(on: try makeImage())

        #expect(model.text == "")
        #expect(model.status == "没有识别到文字")
        #expect(log.values.isEmpty)
    }

    @Test func failureShowsReasonAndDoesNotCopy() async throws {
        let log = CopyLog()
        let model = OCRResultModel(recognize: { _ in throw Boom() }, copy: { log.values.append($0) })

        await model.run(on: try makeImage())

        #expect(model.status == "识别失败：图片无法处理")
        #expect(!model.isRecognizing)
        #expect(log.values.isEmpty)
    }

    @Test func copyAgainUsesEditedText() async throws {
        let log = CopyLog()
        let model = OCRResultModel(recognize: { _ in "识别有错字" }, copy: { log.values.append($0) })
        await model.run(on: try makeImage())

        model.text = "识别没有错字"
        model.copyCurrentText()

        #expect(log.values == ["识别有错字", "识别没有错字"])
    }

    @Test func copyAgainWithEmptyTextDoesNothing() {
        let log = CopyLog()
        let model = OCRResultModel(recognize: { _ in "" }, copy: { log.values.append($0) })
        model.copyCurrentText()
        #expect(log.values.isEmpty)
    }

    @Test func newRunClearsPreviousText() async throws {
        var results = ["第一次", ""]
        let model = OCRResultModel(recognize: { _ in results.removeFirst() }, copy: { _ in })

        await model.run(on: try makeImage())
        await model.run(on: try makeImage())

        #expect(model.text == "")
        #expect(model.status == "没有识别到文字")
    }
}
```

`Tests/ScreenshotModuleTests/ScreenshotActionsTests.swift`:

```swift
import Foundation
import Testing
@testable import ScreenshotModule

@MainActor
@Suite struct ScreenshotActionsTests {
    @Test func savedMessageNamesTheFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mykit-shots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let message = ScreenshotActions.message(for: .saved(folder.appendingPathComponent("a.png")))

        #expect(message == "已保存到 \(folder.lastPathComponent)")
    }

    @Test func fallbackAndFailureMessages() {
        #expect(ScreenshotActions.message(for: .savedToFallback(URL(fileURLWithPath: "/tmp/a.png"))) == "保存失败，已改存到桌面")
        #expect(ScreenshotActions.message(for: .failed) == "保存失败")
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'PinZoom' in scope` 等。

- [ ] **Step 3: 写贴图（三个文件）**

`Sources/ScreenshotModule/PinZoom.swift`:

```swift
import CoreGraphics

/// 贴图的滚轮缩放。纯函数。
public enum PinZoom {
    public static let range: ClosedRange<CGFloat> = 0.1...5.0
    /// 滚轮每 1 个单位改变 1%
    public static let sensitivity: CGFloat = 0.01

    /// 向上滚（deltaY > 0）放大，向下滚缩小；结果夹在 10%…500%。
    public static func scale(current: CGFloat, scrollDeltaY: CGFloat) -> CGFloat {
        let next = current * (1 + scrollDeltaY * sensitivity)
        return min(max(next, range.lowerBound), range.upperBound)
    }

    /// 以窗口中心为锚点，算出缩放后的窗口 frame。baseSize 是 100% 时的大小。
    public static func frame(current: CGRect, baseSize: CGSize, scale: CGFloat) -> CGRect {
        let size = CGSize(width: (baseSize.width * scale).rounded(), height: (baseSize.height * scale).rounded())
        return CGRect(
            x: (current.midX - size.width / 2).rounded(),
            y: (current.midY - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }
}
```

`Sources/ScreenshotModule/PinWindow.swift`:

```swift
import AppKit

/// 贴图窗口的右键菜单要做的事，由 PinManager 转给 ScreenshotActions。
enum PinMenuAction {
    case copy, save, recognize, close, closeAll
}

/// 一张贴图：无边框、浮在所有窗口上面、不抢焦点。
final class PinWindow: NSPanel {
    let image: CGImage
    let baseSize: CGSize
    var onMenuAction: ((PinWindow, PinMenuAction) -> Void)?
    private(set) var zoom: CGFloat = 1

    /// screenRect：AppKit 全局坐标，贴图出现的位置（= 截图时选区的位置）
    init(image: CGImage, screenRect: CGRect) {
        self.image = image
        self.baseSize = screenRect.size
        super.init(
            contentRect: screenRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false        // 拖动由 PinContentView 自己处理，这样才能同时识别双击
        contentView = PinContentView(image: image, owner: self)
        setFrame(screenRect, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func applyScroll(deltaY: CGFloat) {
        let next = PinZoom.scale(current: zoom, scrollDeltaY: deltaY)
        guard next != zoom else { return }
        zoom = next
        setFrame(PinZoom.frame(current: frame, baseSize: baseSize, scale: zoom), display: true)
    }

    fileprivate func send(_ action: PinMenuAction) {
        onMenuAction?(self, action)
    }
}

private final class PinContentView: NSView {
    private weak var owner: PinWindow?

    init(image: CGImage, owner: PinWindow) {
        self.owner = owner
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            owner?.send(.close)                    // 双击关闭
        } else {
            window?.performDrag(with: event)       // 拖动移动
        }
    }

    override func scrollWheel(with event: NSEvent) {
        owner?.applyScroll(deltaY: event.scrollingDeltaY)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let entries: [(String, Selector)] = [
            ("复制", #selector(copyImage)),
            ("保存", #selector(saveImage)),
            ("识别文字", #selector(recognizeText)),
        ]
        for (title, action) in entries {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let close = NSMenuItem(title: "关闭", action: #selector(closePin), keyEquivalent: "")
        close.target = self
        menu.addItem(close)
        let closeAll = NSMenuItem(title: "关闭全部贴图", action: #selector(closeAllPins), keyEquivalent: "")
        closeAll.target = self
        menu.addItem(closeAll)
        return menu
    }

    @objc private func copyImage() { owner?.send(.copy) }
    @objc private func saveImage() { owner?.send(.save) }
    @objc private func recognizeText() { owner?.send(.recognize) }
    @objc private func closePin() { owner?.send(.close) }
    @objc private func closeAllPins() { owner?.send(.closeAll) }
}
```

`Sources/ScreenshotModule/PinManager.swift`:

```swift
import AppKit

/// 管理所有贴图窗口。
@MainActor
final class PinManager {
    /// 右键菜单里的 复制 / 保存 / 识别文字：参数是 (操作, 图片, 图片的 pt 尺寸)
    var onImageAction: ((CaptureAction, CGImage, CGSize) -> Void)?

    private var pins: [PinWindow] = []

    var count: Int { pins.count }

    func pin(image: CGImage, at screenRect: CGRect) {
        let window = PinWindow(image: image, screenRect: screenRect)
        window.onMenuAction = { [weak self] window, action in
            self?.handle(action, from: window)
        }
        pins.append(window)
        window.orderFrontRegardless()
    }

    func closeAll() {
        for pin in pins {
            pin.close()
        }
        pins.removeAll()      // 释放图像
    }

    private func handle(_ action: PinMenuAction, from window: PinWindow) {
        switch action {
        case .copy: onImageAction?(.copy, window.image, window.baseSize)
        case .save: onImageAction?(.save, window.image, window.baseSize)
        case .recognize: onImageAction?(.recognize, window.image, window.baseSize)
        case .close:
            window.close()
            pins.removeAll { $0 === window }
        case .closeAll:
            closeAll()
        }
    }
}
```

- [ ] **Step 4: 写识别结果窗口与操作执行（三个文件）**

`Sources/ScreenshotModule/OCRResultModel.swift`:

```swift
import CoreGraphics
import Foundation

/// "识别结果"窗口背后的状态。识别和复制都通过闭包注入，方便测试。
@MainActor
final class OCRResultModel: ObservableObject {
    @Published var text = ""
    @Published private(set) var status = ""
    @Published private(set) var isRecognizing = false

    private let recognize: (CGImage) async throws -> String
    private let copy: (String) -> Void
    /// 每次识别加一；旧的识别结果回来时如果代数变了就丢弃
    private var generation = 0

    init(recognize: @escaping (CGImage) async throws -> String, copy: @escaping (String) -> Void) {
        self.recognize = recognize
        self.copy = copy
    }

    func run(on image: CGImage) async {
        generation += 1
        let expected = generation
        text = ""
        status = "正在识别…"
        isRecognizing = true
        let outcome: Result<String, Error>
        do {
            outcome = .success(try await recognize(image))
        } catch {
            outcome = .failure(error)
        }
        guard expected == generation else { return }
        isRecognizing = false
        switch outcome {
        case .success(let recognized) where recognized.isEmpty:
            status = "没有识别到文字"
        case .success(let recognized):
            text = recognized
            copy(recognized)
            status = "✓ 已复制全文"
        case .failure(let error):
            status = "识别失败：\(error.localizedDescription)"
        }
    }

    /// "重新复制"：复制文本区当前的全部内容（含用户的修改）。
    func copyCurrentText() {
        guard !text.isEmpty else { return }
        copy(text)
        status = "✓ 已复制全文"
    }
}
```

`Sources/ScreenshotModule/OCRResultWindowController.swift`:

```swift
import AppKit
import Core
import SwiftUI

/// "识别结果"窗口。普通窗口（会激活 MyKit，因为要打字）；每次识别复用同一个窗口。
@MainActor
final class OCRResultWindowController {
    private let model = OCRResultModel(
        recognize: { try await TextRecognizer.recognize($0) },
        copy: { PasteService.writeFromMyKit($0) }
    )
    private var window: NSWindow?

    func recognize(_ image: CGImage) {
        show()
        Task { await model.run(on: image) }
    }

    private func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "识别结果"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 320, height: 200)
            window.contentView = NSHostingView(rootView: OCRResultView(model: model, onClose: { [weak window] in
                window?.close()
            }))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct OCRResultView: View {
    @ObservedObject var model: OCRResultModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $model.text)
                .font(.system(size: 14))
                .padding(8)
                .overlay {
                    if model.isRecognizing {
                        ProgressView()
                    }
                }
            Divider()
            HStack {
                Text(model.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("重新复制") { model.copyCurrentText() }
                    .disabled(model.text.isEmpty)
                Button("关闭", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 320, minHeight: 200)
    }
}
```

`Sources/ScreenshotModule/ScreenshotActions.swift`:

```swift
import AppKit
import Core

/// 复制 / 保存 / 识别文字 / 贴图 的执行，以及它们的提示文案。
@MainActor
final class ScreenshotActions {
    let pins = PinManager()
    private let settings: ScreenshotSettings
    private let saver: ScreenshotSaver
    private let ocrWindow = OCRResultWindowController()

    init(settings: ScreenshotSettings, saver: ScreenshotSaver = ScreenshotSaver()) {
        self.settings = settings
        self.saver = saver
        pins.onImageAction = { [weak self] action, image, pointSize in
            self?.perform(action, image: image, pointSize: pointSize, screenRect: nil)
        }
    }

    /// screenRect 只有贴图用得到；从贴图的右键菜单发起的操作传 nil。
    func perform(_ action: CaptureAction, image: CGImage, pointSize: CGSize, screenRect: CGRect?) {
        switch action {
        case .copy:
            let ok = PasteService.write(image: image, pointSize: pointSize)
            Toast.show(ok ? "已复制" : "复制失败")
        case .save:
            let outcome = saver.save(image, pointSize: pointSize, to: settings.saveFolder)
            Toast.show(Self.message(for: outcome))
        case .recognize:
            ocrWindow.recognize(image)
        case .pin:
            guard let screenRect else { return }
            pins.pin(image: image, at: screenRect)
        }
    }

    /// 保存结果 → 提示文案。文件夹用系统显示的名字（"桌面"而不是 "Desktop"）。
    static func message(for outcome: SaveOutcome) -> String {
        switch outcome {
        case .saved(let url):
            return "已保存到 \(FileManager.default.displayName(atPath: url.deletingLastPathComponent().path))"
        case .savedToFallback:
            return "保存失败，已改存到桌面"
        case .failed:
            return "保存失败"
        }
    }
}
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 183 tests in 31 suites passed`，零警告。

- [ ] **Step 6: Commit**

```bash
git add Sources/ScreenshotModule Tests/ScreenshotModuleTests
git commit -m "feat(screenshot): pinned images, OCR result window, action execution with toasts"
```

---

### Task 7: 总装 —— 模块、授权引导、设置页、快捷键接线、使用说明、验收

**Files:**
- Create: `Sources/ScreenshotModule/ScreenRecordingGuideWindowController.swift`, `Sources/ScreenshotModule/ScreenshotSettingsView.swift`, `Sources/ScreenshotModule/ScreenshotModule.swift`
- Modify: `Package.swift`, `Sources/MyKit/AppDelegate.swift`, `README.md`
- Test: `Tests/ScreenshotModuleTests/ScreenshotModuleTests.swift`

**Interfaces:**
- Consumes: `AppModule`、`ModuleRegistry`（已有）；`GlobalKeyTap.register`、`KeyCombo.controlCommandA`（Task 1）；`Permissions` 的屏幕录制方法、`Toast`（Task 2）；`ScreenCapturer`、`WindowLocator.visibleWindowBounds()`、`CaptureOverlayController`（Task 3、5）；`ScreenshotActions`、`ScreenshotSettings`（Task 4、6）
- Produces:
  - `@MainActor public final class ScreenshotModule: NSObject, AppModule { init(defaults: UserDefaults = .standard); func startCapture() }`，`id = "screenshot"`，`name = "截图"`，菜单项「截图」（显示 ⌃⌘A）、「关闭所有贴图」，设置页
  - 可安装使用的 `/Applications/MyKit.app`

- [ ] **Step 1: 写失败的测试 `Tests/ScreenshotModuleTests/ScreenshotModuleTests.swift`**

```swift
import AppKit
import Foundation
import Testing
@testable import ScreenshotModule

@MainActor
@Suite struct ScreenshotModuleTests {
    private func makeModule() -> ScreenshotModule {
        let suite = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ScreenshotModule(defaults: defaults)
    }

    @Test func exposesIdentityAndSettings() {
        let module = makeModule()
        #expect(module.id == "screenshot")
        #expect(module.name == "截图")
        #expect(module.settingsView != nil)
    }

    @Test func menuHasCaptureWithShortcutAndCloseAllPins() {
        let module = makeModule()      // 菜单项的 target 是弱引用，模块必须活着
        let items = module.menuItems

        #expect(items.map(\.title) == ["截图", "关闭所有贴图"])
        #expect(items[0].keyEquivalent == "a")
        #expect(items[0].keyEquivalentModifierMask == [.control, .command])
        #expect(items.allSatisfy { $0.target != nil && $0.action != nil })
    }

    @Test func startAndStopDoNotRequirePermissions() throws {
        let module = makeModule()
        try module.start()
        module.stop()
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'ScreenshotModule' in scope`（注意：此时模块名存在、类还不存在，报错可能写成 `'ScreenshotModule' cannot be constructed` 或 `module 'ScreenshotModule' has no member…`，都算预期失败）。

- [ ] **Step 3: 写模块的三个文件**

`Sources/ScreenshotModule/ScreenRecordingGuideWindowController.swift`:

```swift
import AppKit
import Core
import SwiftUI

/// 第一次截图时，如果还没有"屏幕录制"授权，就弹这个引导窗口。
@MainActor
final class ScreenRecordingGuideWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "截图需要授权"
            window.contentView = NSHostingView(rootView: ScreenRecordingGuideView())
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct ScreenRecordingGuideView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("截图需要「屏幕录制」权限")
                .font(.title2.bold())
            Text("这是 macOS 对所有截图软件的统一要求（微信、Snipaste 也一样）。MyKit 只在你按下截图快捷键的那一刻读取屏幕画面，不录像、不联网。")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("1. 点击下面的「打开系统设置」")
                Text("2. 在「录屏与系统录音」列表里找到 MyKit，打开右边的开关")
                Text("3. 回到这里，点「重新启动 MyKit」—— 这项权限要重启后才生效")
            }
            .foregroundStyle(.secondary)

            HStack {
                Button("打开系统设置") {
                    Permissions.openScreenRecordingSettings()
                }
                .buttonStyle(.borderedProminent)
                Button("重新启动 MyKit") {
                    Permissions.relaunch()
                }
            }

            Text("没有这项权限不影响剪切板功能。以后系统可能会定期询问「是否继续允许 MyKit 录制屏幕」，选「继续允许」即可。")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 460)
    }
}
```

`Sources/ScreenshotModule/ScreenshotSettingsView.swift`:

```swift
import AppKit
import SwiftUI

struct ScreenshotSettingsView: View {
    /// 空字符串 = 还没设置过 = 桌面
    @AppStorage private var folderPath: String

    init(defaults: UserDefaults) {
        _folderPath = AppStorage(wrappedValue: "", ScreenshotSettings.saveFolderKey, store: defaults)
    }

    var body: some View {
        LabeledContent("快捷键") {
            Text("⌃⌘A")
                .foregroundStyle(.secondary)
        }
        LabeledContent("保存位置") {
            HStack {
                Text(folderName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Button("选择…", action: chooseFolder)
            }
        }
    }

    private var folderName: String {
        folderPath.isEmpty ? "桌面" : FileManager.default.displayName(atPath: folderPath)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择截图保存到哪个文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
        }
    }
}
```

`Sources/ScreenshotModule/ScreenshotModule.swift`:

```swift
import AppKit
import Core
import SwiftUI
import os

@MainActor
public final class ScreenshotModule: NSObject, AppModule {
    public let id = "screenshot"
    public let name = "截图"

    private let defaults: UserDefaults
    private let actions: ScreenshotActions
    private let guide = ScreenRecordingGuideWindowController()
    private let log = Logger(subsystem: "com.imiros.mykit", category: "screenshot")
    /// 正在进行的截图会话。同一时间只允许一个。
    private var session: CaptureOverlayController?
    /// 已触发、正在定格画面（遮罩还没出现）
    private var isStarting = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.actions = ScreenshotActions(settings: ScreenshotSettings(defaults: defaults))
        super.init()
    }

    public func start() throws {}

    public func stop() {
        session?.end()
        actions.pins.closeAll()
    }

    /// 开始一次截图（⌃⌘A 或菜单）。没有"屏幕录制"授权时改为弹出引导窗口。
    public func startCapture() {
        if let session {
            // 保底退出：截图进行中再按一次 ⌃⌘A 直接结束截图。这条路走全局键盘监听，
            // 不依赖遮罩面板拿到键盘焦点，所以即使 Esc 失灵屏幕也不会被卡住。
            session.end()
            return
        }
        guard !isStarting else { return }                      // 正在定格画面：忽略
        guard Permissions.isScreenRecordingGranted else {
            Permissions.requestScreenRecording()              // 让 MyKit 出现在系统设置的列表里
            guide.show()
            return
        }

        isStarting = true
        let screens = ScreenCapturer.currentScreens()
        let windows = WindowLocator.visibleWindowBounds()      // 与定格画面同一时刻的窗口布局
        Task { [weak self] in
            let outcome: Result<[DisplaySnapshot], Error>
            do {
                outcome = .success(try await ScreenCapturer.captureAll(screens: screens))
            } catch {
                outcome = .failure(error)
            }
            self?.captureDidFinish(outcome, windows: windows)
        }
    }

    private func captureDidFinish(_ outcome: Result<[DisplaySnapshot], Error>, windows: [CGRect]) {
        isStarting = false
        switch outcome {
        case .success(let snapshots):
            let controller = CaptureOverlayController(snapshots: snapshots, cgWindows: windows)
            controller.onFinish = { [weak self] action, result in
                self?.actions.perform(action, image: result.image, pointSize: result.pointSize, screenRect: result.screenRect)
            }
            controller.onEnd = { [weak self] in
                self?.session = nil
            }
            session = controller
            controller.begin()
        case .failure(let error):
            log.error("截图失败: \(String(describing: error), privacy: .public)")
            Toast.show("截图失败")
            if !Permissions.isScreenRecordingGranted {
                guide.show()
            }
        }
    }

    // MARK: 菜单与设置

    private lazy var captureMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "截图", action: #selector(captureFromMenu), keyEquivalent: "a")
        item.keyEquivalentModifierMask = [.control, .command]     // 在菜单里显示 ⌃⌘A
        item.target = self
        return item
    }()

    private lazy var closePinsMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "关闭所有贴图", action: #selector(closeAllPinsFromMenu), keyEquivalent: "")
        item.target = self
        return item
    }()

    public var menuItems: [NSMenuItem] {
        [captureMenuItem, closePinsMenuItem]
    }

    public var settingsView: AnyView? {
        AnyView(ScreenshotSettingsView(defaults: defaults))
    }

    @objc private func captureFromMenu() {
        // 等菜单完全收起再定格画面，否则菜单本身会被截进去
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.startCapture()
        }
    }

    @objc private func closeAllPinsFromMenu() {
        actions.pins.closeAll()
    }
}
```

- [ ] **Step 4: 更新 `Package.swift`（完整内容；`MyKit` 增加对 `ScreenshotModule` 的依赖）**

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
        .executableTarget(name: "MyKit", dependencies: ["Core", "ClipboardModule", "ScreenshotModule"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "ClipboardModuleTests", dependencies: ["ClipboardModule"]),
        .testTarget(name: "ScreenshotModuleTests", dependencies: ["ScreenshotModule"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 5: 更新 `Sources/MyKit/AppDelegate.swift`（完整内容；注册截图模块并接上 ⌃⌘A）**

```swift
import AppKit
import ClipboardModule
import Core
import ScreenshotModule
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.imiros.mykit", category: "app")
    private let registry = ModuleRegistry()
    private let eventTap = GlobalKeyTap()
    private let accessibilityWatcher = AccessibilityWatcher()
    private let onboarding = OnboardingWindowController()
    private var clipboard: ClipboardModule?
    private var screenshot: ScreenshotModule?
    private var statusBar: StatusBarController?
    private var settingsWindow: SettingsWindowController?
    private var eventTapFailed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        registry.startAll()
        for failure in registry.failures {
            log.error("模块 \(failure.id, privacy: .public) 启动失败: \(String(describing: failure.error), privacy: .public)")
        }

        let settingsWindow = SettingsWindowController(modules: registry.modules)
        self.settingsWindow = settingsWindow
        statusBar = StatusBarController(
            moduleMenuItems: registry.menuItems,
            onOpenSettings: { settingsWindow.show() }
        )

        eventTap.onDoubleTap = { [weak self] in
            self?.clipboard?.togglePanel()
        }
        eventTap.register(.controlCommandA) { [weak self] in
            self?.screenshot?.startCapture()
        }
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

- [ ] **Step 6: 跑测试并构建**

Run: `scripts/test.sh && scripts/build-app.sh`
Expected: `✔ Test run with 186 tests in 32 suites passed`，零警告；构建输出 `designated => identifier "com.imiros.mykit" and certificate leaf = H"…"`（与之前相同的 H 值）和 `完成：build/MyKit.app`。

- [ ] **Step 7: 用下面的内容整体替换 `README.md`**

````markdown
# MyKit

Mac 菜单栏小工具箱。目前的功能：

- **剪切板历史** —— 双击 Option 呼出，保留最近 7 天复制过的文字，可搜索，回车直接粘贴；每条记录前面的图标表示它是从哪个 App 复制的。
- **截图** —— 按 `⌃⌘A`，框选或点选窗口，然后复制 / 保存 / 识别文字 / 贴在屏幕上。

## 安装

在"终端"里进入本目录，依次运行：

```bash
scripts/create-dev-cert.sh   # 只需要运行一次
scripts/build-app.sh
scripts/install.sh
```

完成后屏幕右上角会出现 MyKit 图标（三层叠起来的方块）。

## 第一次使用：授权

MyKit 需要两项系统授权，都只需要做一次。

**辅助功能**（双击 Option、`⌃⌘A`、自动粘贴都靠它）—— 第一次启动会弹出引导窗口：

1. 点「打开系统设置」
2. 在「辅助功能」列表里找到 MyKit，打开右边的开关
3. 引导窗口会自动关闭，授权完成

**屏幕录制**（截图靠它）—— 第一次按 `⌃⌘A` 时会弹出引导窗口：

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

按 `⌃⌘A`（或点右上角图标 →「截图」），屏幕会定格并变暗：

- 把鼠标移到某个窗口上，它会变亮，**单击**就选中整个窗口；
- 或者**按住拖动**，框出任意一块区域；
- 选好后可以拖边上的小方块改大小、在选区里拖动改位置。

选区旁边会出现工具条：

| 按钮 | 键盘 | 效果 |
|---|---|---|
| 复制 | 回车 / `⌘C` / 双击选区 | 图片进剪切板，可以直接粘贴到微信、文档里 |
| 保存 | `⌘S` | 存成 PNG 文件（默认在桌面，可在偏好设置里改） |
| 识别文字 | `⌘R` | 弹出"识别结果"窗口，文字可以改；全文已经自动复制 |
| 贴图 | `⌘T` | 截图原地浮在屏幕上，方便对照着看 |
| 取消 | Esc / 右键 | 第一次清除选区重新选，再按一次退出截图 |

**贴图**：拖动可以移动，滚轮缩放，双击关闭；右键有 复制 / 保存 / 识别文字 / 关闭 / 关闭全部贴图。右上角菜单里也有「关闭所有贴图」。

**和微信抢快捷键？** 微信的截图默认也是 `⌃⌘A`。如果按下后出来的是微信的截图，到微信「设置 → 快捷键」里把"截取屏幕"关掉或改成别的键。

## 退出

**左键或右键**点击右上角的 MyKit 图标 →「退出 MyKit」。

同一个菜单里还有：打开剪切板、暂停记录、截图、关闭所有贴图、偏好设置（保留天数、开机自启、清空历史、截图保存位置）。

## 数据在哪里

剪切板历史：`~/Library/Application Support/MyKit/clipboard.sqlite`，只保存在本机，不联网。从密码管理器复制的密码不会被记录。
截图：只有你点「保存」时才会写文件；文字识别在本机完成，不联网。

## 更新

改了代码之后重新运行 `scripts/build-app.sh && scripts/install.sh`，不需要重新授权。

## 开发

```bash
scripts/test.sh                                   # 跑全部单元测试
scripts/test.sh --filter SelectionModelTests      # 只跑一组
```

设计文档：`docs/superpowers/specs/`；实现计划：`docs/superpowers/plans/`
````

- [ ] **Step 8: 安装并确认启动正常**

Run:

```bash
scripts/install.sh
perl -e 'select(undef,undef,undef,3)'
pgrep -x MyKit && echo "MyKit 正在运行"
/usr/bin/log show --last 1m --predicate 'subsystem == "com.imiros.mykit"' --info | grep -E "MyKit 已启动|失败"
```

Expected: 打印进程号和 `MyKit 正在运行`；日志里有 `MyKit 已启动，辅助功能授权=true…`，没有"失败"字样。

- [ ] **Step 9: 手动验收（需要人来操作；每一条都写了"怎么做"和"应该看到什么"，任何一条不符合就修复后重测）**

**A. 授权**

1. 按 `⌃⌘A`。→ 第一次应该**不**出现截图遮罩，而是弹出「截图需要授权」窗口（系统可能同时弹一个自己的提示，关掉即可）。
2. 点「打开系统设置」，在「录屏与系统录音」里打开 MyKit 的开关（系统若提示"退出并重新打开"，选稍后）。回到引导窗口点「重新启动 MyKit」。→ 右上角图标消失一下又出现。
3. 再按 `⌃⌘A`。→ 屏幕定格并变暗，鼠标变成十字。按 `Esc` 退出。

**B. 快捷键**

4. 在"文本编辑"里打字时按 `⌃⌘A`，然后按 `Esc`。→ 文档里**没有**多出任何字符，也没有"咚"的提示音（按键被 MyKit 吞掉了）。
5. 点右上角 MyKit 图标 →「截图」（菜单项右边显示 ⌃⌘A）。→ 同样进入截图，而且截到的画面里**没有**那个菜单。
6. 微信冲突实测：打开微信并登录，确认微信「设置 → 快捷键 → 截取屏幕」是 `⌃⌘A`。按 `⌃⌘A`。→ 记下出现的是谁的截图界面：只出现 MyKit 的 = 最好；出现微信的、或两个都出现 = 按 README「和微信抢快捷键？」一节，到微信里关掉或改掉它的快捷键，再试一次应只出现 MyKit 的。把实测结果写进本任务的提交信息里。
7. 截图进行中再按一次 `⌃⌘A`。→ 直接退出截图，屏幕恢复正常（保底退出；不会叠出第二层遮罩）。

**C. 选区**

8. 进入截图后，把鼠标依次移到几个不同的窗口上。→ 鼠标下的窗口整个变亮、带蓝色边框，其余变暗；移到桌面空白处时没有窗口变亮。
9. 单击一个变亮的窗口。→ 选中整个窗口：四周 8 个小方块，左上角显示"宽 × 高"，下方出现工具条（贴图 / 识别文字 / 保存 / 复制 / ✕）。
10. 按 `Esc` 清除选区，然后按住鼠标拖出一块区域。→ 拖动时尺寸数字跟着变、工具条不显示；松手后工具条出现。
11. 拖选区边上和角上的小方块；在选区里面按住拖动。→ 大小 / 位置跟着变，始终出不了屏幕；拖过头也不会翻转或缩成 0。
12. 把选区拖到贴着屏幕底边。→ 工具条改到选区上方；把选区拉到几乎整屏 → 工具条出现在选区内右下角。
13. 已有选区时，在选区外面按住拖动。→ 换成新拖出的选区。
14. 已有选区时按 `Esc`（或右键）。→ 第一次只清除选区、仍在截图状态；再按一次退出截图，屏幕恢复正常。

**D. 五个操作**

15. 选一块区域后按回车。→ 遮罩消失，右上角闪一下「已复制」；到微信或"预览"（文件 → 从剪贴板新建）里粘贴，是刚才那块区域，Retina 屏上文字清晰不发虚。再试 `⌘C` 和双击选区，效果相同。
16. 选一块区域后按 `⌘S`。→ 提示「已保存到 桌面」；桌面上出现 `MyKit 2026-…png`。第一次可能弹"允许 MyKit 访问桌面文件夹"，选允许。用"预览"打开，显示尺寸和选区一致（不是放大两倍的）。
17. 选一块有中英文的区域后按 `⌘R`。→ 弹出「识别结果」窗口，先显示转圈，随后出现文字，底部显示「✓ 已复制全文」；到别处直接粘贴就是全文。在窗口里改几个字，点「重新复制」，再粘贴 → 是改过的内容。点「关闭」。
18. 选一块没有文字的区域（纯色背景）后按 `⌘R`。→ 窗口显示「没有识别到文字」，剪切板内容没有被改动。
19. 双击 Option 打开剪切板历史。→ 刚才识别的文字在列表里，前面的图标是 **MyKit 自己的图标**，右下方写着「来自 MyKit」。
20. 选一块区域后按 `⌘T`。→ 截图原地"贴"在屏幕上（位置、大小与选区完全重合），带细边和阴影。

**E. 贴图**

21. 拖动贴图；在贴图上滚动滚轮；切换到别的 App、切换桌面、进入某个全屏 App。→ 能移动；能放大缩小（以中心为准，最小约 10%、最大 5 倍）；贴图始终浮在最上面，全屏 App 上也在。拖动和滚动时**不会**把 MyKit 变成前台 App（菜单栏左上角的 App 名不变）。
22. 再贴两张。右键其中一张。→ 菜单有 复制 / 保存 / 识别文字 / 关闭 / 关闭全部贴图，各项都能用（复制后可粘贴、保存后桌面有文件、识别文字弹出结果窗口）。
23. 双击一张贴图 → 只关闭这一张。点右上角图标 →「关闭所有贴图」→ 剩下的全部消失。
24. 屏幕上留一张贴图，再按 `⌃⌘A` 截图。→ 贴图也出现在定格画面里（所见即所得）。

**F. 设置与回退**

25. 右上角图标 → 偏好设置。→ 有「截图」一节，显示快捷键 ⌃⌘A 和保存位置「桌面」。点「选择…」选一个别的文件夹，截图保存 → 提示「已保存到 <那个文件夹>」，文件在那里。
26. 在访达里把那个文件夹删掉，再截图保存。→ 提示「保存失败，已改存到桌面」，文件出现在桌面。

**G. 多显示器与资源（有第二块显示器才做 27）**

27. 两块屏都定格变暗；在副屏上框选、贴图 → 贴图出现在副屏的原位置；在一块屏上有选区时到另一块屏上点选 → 前一块屏的选区消失。
28. 打开"活动监视器"搜 MyKit，记下内存；连续截图 10 次（每次都按 Esc 退出），关闭所有贴图，等十几秒。→ 内存回落到接近开始时的水平，没有每截一次涨一截。
29. 回归：双击 Option 的剪切板面板、回车粘贴、右键菜单栏图标 →「退出 MyKit」都和以前一样。

- [ ] **Step 10: Commit**

```bash
git add Package.swift Sources README.md Tests
git commit -m "feat: screenshot module phase 1 - capture, window detection, copy/save/OCR/pin, guide and settings"
```
