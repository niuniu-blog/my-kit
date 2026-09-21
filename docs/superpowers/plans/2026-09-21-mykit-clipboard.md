# MyKit 应用外壳 + 剪切板历史 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做出一个 macOS 菜单栏常驻应用 MyKit：双击 Option 弹出剪切板历史面板（保留 7 天、可搜索），回车直接粘贴到当前 App；右上角图标可左/右键点出菜单并退出。

**Architecture:** 一个 SwiftPM 包，三层 Target：`Core`（模块协议、双击检测、事件监听、浮动面板、粘贴、权限）→ `ClipboardModule`（监听、SQLite+FTS5 存储、面板 UI）→ `MyKit` 可执行（菜单栏、设置、引导）。纯逻辑与系统 API 分离：状态机、过滤规则、存储、ViewModel 都可单元测试；系统相关部分用手动验收清单覆盖。脚本把可执行文件组装成 `.app` 并用固定的自签名证书签名。

**Tech Stack:** Swift 6.4（语言模式 5）、AppKit + SwiftUI、系统 SQLite3（FTS5 trigram）、CryptoKit、ServiceManagement、Swift Testing、bash 脚本。无第三方依赖。

**Spec:** `docs/superpowers/specs/2026-09-21-mykit-clipboard-design.md`

## Global Constraints

- 运行环境：macOS 27，只有 Command Line Tools，**没有 Xcode**。不要使用 `xcodebuild`、`.xcodeproj`、XCTest。
- 构建必须带 `--build-system native`（默认的 swiftbuild 在仅 CLT 环境下报 "Could not initialize build system"）。会出现一条 deprecated 警告，忽略即可。
- 跑测试**只用** `scripts/test.sh`（它补上了 Swift Testing 的框架 / 宏插件 / rpath 参数）；直接 `swift test` 会报 `no such module 'Testing'`。
- 测试框架：Swift Testing（`import Testing`、`@Test`、`#expect`、`#require`）。
- `Package.swift`：`// swift-tools-version: 6.0`，`platforms: [.macOS(.v14)]`，`swiftLanguageModes: [.v5]`。
- **不要写 `@State`**：macOS 27 SDK 里它是宏（`SwiftUIMacros.StateMacro`），宏插件只随 Xcode 提供，CLT 下编译报 `plugin for module 'SwiftUIMacros' not found`。一律用 `Core` 里的别名 `@ViewState`（= `SwiftUI.State` 属性包装器，行为完全相同，Task 1 创建）。`@FocusState`、`@AppStorage`、`@ObservedObject`、`@Published` 不受影响。同理不要用 `#Preview`、`@Entry`、`@Animatable`。
- 最低系统 macOS 14；高于 14 的 API（如 `NSPasteboard.accessBehavior`，15.4）必须包在 `#available` 里。
- 不引入任何第三方依赖。
- bundle id：`com.imiros.mykit`；软件名：`MyKit`；日志 subsystem：`com.imiros.mykit`。
- 自己写入剪切板的标记类型：`com.imiros.mykit.own-write`。
- 数据库：`~/Library/Application Support/MyKit/clipboard.sqlite`。
- 签名：证书名 `MyKit Dev`，专用钥匙串 `~/Library/Keychains/mykit-dev.keychain-db`，钥匙串密码 `mykit-dev`（它只保护一张本地自签名开发证书，不是机密）。**不要**用 ad-hoc 签名（`-s -`），否则每次重编译辅助功能授权都会失效。
- 事件监听用 `CGEvent.tapCreate(... options: .defaultTap ...)`（只需"辅助功能"一项授权；`.listenOnly` 会额外要求"输入监控"）。回调里必须原样返回事件。
- 所有面向用户的文案用简体中文。
- 每个任务结束时 `scripts/test.sh` 必须全绿，然后提交。

## File Structure

```
Package.swift
.gitignore
README.md                                   用户向的中文使用说明（Task 7）
Resources/Info.plist                        LSUIElement 等
scripts/test.sh                             跑测试（补 CLT 参数）
scripts/create-dev-cert.sh                  一次性创建签名证书 + 专用钥匙串
scripts/build-app.sh                        编译 → 组装 build/MyKit.app → 签名
scripts/install.sh                          装到 /Applications 并启动
scripts/make-icon.swift                     生成 AppIcon.iconset

Sources/Core/
  AppModule.swift                           模块协议
  ModuleRegistry.swift                      注册 / 启停模块、汇总菜单项
  ViewState.swift                           @State 的别名（绕开 macOS 27 SDK 的宏插件问题）
  DoubleTapDetector.swift                   纯状态机：双击修饰键
  ModifierEventTranslator.swift             CGEvent 字段 → 状态机事件（纯函数）
  ModifierEventTap.swift                    CGEventTap 包装
  Permissions.swift                         辅助功能 / 剪切板访问检查 + AccessibilityWatcher
  PasteService.swift                        写剪切板（带自有标记）+ 发送 ⌘V
  FloatingPanel.swift                       不抢焦点的 NSPanel

Sources/ClipboardModule/
  SQLiteDatabase.swift                      SQLite3 C API 的最小包装
  ClipboardItem.swift                       数据模型 + 单行摘要
  ClipboardStore.swift                      actor：建表、add/touch/search/delete/purge、损坏恢复
  CaptureFilter.swift                       纯函数：这次剪切板变化要不要记
  ClipboardSettings.swift                   UserDefaults 包装（保留天数）
  ClipboardMonitor.swift                    轮询 changeCount → 过滤 → 入库
  ClipboardPanelViewModel.swift             搜索 / 选择 / 分页 / 删除
  ClipboardPanelView.swift                  SwiftUI 面板界面
  ClipboardPanelController.swift            面板显示、按键处理、粘贴
  ClipboardSettingsView.swift               保留天数 + 清空历史
  ClipboardModule.swift                     实现 AppModule，组装以上各件

Sources/MyKit/
  main.swift                                入口
  AppDelegate.swift                         组装外壳
  StatusBarController.swift                 右上角图标 + 菜单（含退出）
  SettingsWindowController.swift            偏好设置窗口（通用 + 各模块）
  OnboardingWindowController.swift          授权引导窗口

Tests/CoreTests/                            ModuleRegistry / DoubleTapDetector / Translator / Watcher / PasteService
Tests/ClipboardModuleTests/                 Store / CaptureFilter / Settings / Monitor / ViewModel / Item 摘要
```

任务顺序：1 可运行骨架（图标 + 退出）→ 2 双击检测 → 3 存储 → 4 监听 → 5 Core 系统服务 → 6 面板与模块 → 7 总装、引导、设置、验收。

---

### Task 1: 可运行骨架 —— 菜单栏图标、退出菜单、构建与签名脚本

**Files:**
- Create: `.gitignore`, `Package.swift`, `Resources/Info.plist`
- Create: `scripts/test.sh`, `scripts/create-dev-cert.sh`, `scripts/build-app.sh`, `scripts/install.sh`, `scripts/make-icon.swift`
- Create: `Sources/Core/AppModule.swift`, `Sources/Core/ModuleRegistry.swift`, `Sources/Core/ViewState.swift`
- Create: `Sources/MyKit/main.swift`, `Sources/MyKit/AppDelegate.swift`, `Sources/MyKit/StatusBarController.swift`
- Test: `Tests/CoreTests/ModuleRegistryTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `@MainActor public protocol AppModule: AnyObject { var id: String { get }; var name: String { get }; func start() throws; func stop(); var menuItems: [NSMenuItem] { get }; var settingsView: AnyView? { get } }`（后两者有默认实现：`[]` / `nil`）
  - `@MainActor public final class ModuleRegistry { init(); func register(_:); func startAll(); func stopAll(); var modules: [AppModule]; var menuItems: [NSMenuItem]; var failures: [(id: String, error: Error)] }`
  - `StatusBarController(moduleMenuItems: [NSMenuItem], onOpenSettings: @escaping () -> Void)`，`func setIcon(_ state: IconState)`，`enum IconState { case normal, paused, warning }`
  - `scripts/test.sh [swift test 的额外参数]`、`scripts/build-app.sh`（产出 `build/MyKit.app`）、`scripts/install.sh`

- [ ] **Step 1: 写 `.gitignore` 和 `Package.swift`**

`.gitignore`:

```
.build/
build/
.swiftpm/
.DS_Store
```

`Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyKit",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Core"),
        .executableTarget(name: "MyKit", dependencies: ["Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: 写 `scripts/test.sh`**

```bash
#!/bin/bash
# 跑全部单元测试。额外参数原样传给 swift test，例如：scripts/test.sh --filter DoubleTapDetectorTests
set -euo pipefail
cd "$(dirname "$0")/.."

DEV_DIR="$(xcode-select -p)"
ARGS=(--build-system native)
# 只有 Command Line Tools（没有 Xcode）时，Swift Testing 的框架、宏插件和运行时路径都要手动指定
if [[ "$DEV_DIR" == *CommandLineTools* ]]; then
  FW="$DEV_DIR/Library/Developer/Frameworks"
  ARGS+=(
    -Xswiftc "-F$FW"
    -Xswiftc -plugin-path -Xswiftc "$DEV_DIR/usr/lib/swift/host/plugins/testing"
    -Xlinker "-F$FW"
    -Xlinker -rpath -Xlinker "$FW"
    -Xlinker -rpath -Xlinker "$DEV_DIR/Library/Developer/usr/lib"
  )
fi

swift test "${ARGS[@]}" "$@"
```

Run: `chmod +x scripts/test.sh`

- [ ] **Step 3: 写失败的测试 `Tests/CoreTests/ModuleRegistryTests.swift`**

```swift
import AppKit
import Testing
@testable import Core

@MainActor
private final class FakeModule: AppModule {
    let id: String
    let name: String
    var shouldFail = false
    var log: [String]
    let items: [NSMenuItem]

    init(id: String, items: [NSMenuItem] = [], log: [String] = []) {
        self.id = id
        self.name = id
        self.items = items
        self.log = log
    }

    struct Boom: Error {}

    func start() throws {
        if shouldFail { throw Boom() }
        log.append("start")
    }

    func stop() { log.append("stop") }

    var menuItems: [NSMenuItem] { items }
}

@MainActor
@Suite struct ModuleRegistryTests {
    @Test func startsAndStopsRegisteredModules() {
        let registry = ModuleRegistry()
        let a = FakeModule(id: "a")
        let b = FakeModule(id: "b")
        registry.register(a)
        registry.register(b)

        registry.startAll()
        registry.stopAll()

        #expect(a.log == ["start", "stop"])
        #expect(b.log == ["start", "stop"])
        #expect(registry.failures.isEmpty)
    }

    @Test func failingModuleDoesNotBlockOthersAndIsNotStopped() {
        let registry = ModuleRegistry()
        let bad = FakeModule(id: "bad")
        bad.shouldFail = true
        let good = FakeModule(id: "good")
        registry.register(bad)
        registry.register(good)

        registry.startAll()
        registry.stopAll()

        #expect(registry.failures.map(\.id) == ["bad"])
        #expect(bad.log.isEmpty)
        #expect(good.log == ["start", "stop"])
    }

    @Test func collectsMenuItemsInRegistrationOrder() {
        let registry = ModuleRegistry()
        registry.register(FakeModule(id: "a", items: [NSMenuItem(title: "A1", action: nil, keyEquivalent: "")]))
        registry.register(FakeModule(id: "b", items: [NSMenuItem(title: "B1", action: nil, keyEquivalent: "")]))

        #expect(registry.menuItems.map(\.title) == ["A1", "B1"])
    }

    @Test func defaultMenuItemsAndSettingsViewAreEmpty() {
        @MainActor final class Bare: AppModule {
            let id = "bare"
            let name = "bare"
            func start() throws {}
            func stop() {}
        }
        let bare = Bare()
        #expect(bare.menuItems.isEmpty)
        #expect(bare.settingsView == nil)
    }
}
```

- [ ] **Step 4: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find type 'AppModule' in scope`（Core 里还没有任何源文件时也可能报 target 为空，同样算预期失败）。

- [ ] **Step 5: 写 `Sources/Core/AppModule.swift` 和 `Sources/Core/ModuleRegistry.swift`**

`Sources/Core/AppModule.swift`:

```swift
import AppKit
import SwiftUI

/// MyKit 的一个功能模块（剪切板、文本片段、截图……）。外壳只通过这个协议认识模块。
@MainActor
public protocol AppModule: AnyObject {
    var id: String { get }
    /// 显示在偏好设置里的中文名
    var name: String { get }
    func start() throws
    func stop()
    /// 放进右上角菜单的菜单项
    var menuItems: [NSMenuItem] { get }
    /// 放进偏好设置窗口的设置页
    var settingsView: AnyView? { get }
}

public extension AppModule {
    var menuItems: [NSMenuItem] { [] }
    var settingsView: AnyView? { nil }
}
```

`Sources/Core/ModuleRegistry.swift`:

```swift
import AppKit

@MainActor
public final class ModuleRegistry {
    public private(set) var modules: [AppModule] = []
    public private(set) var failures: [(id: String, error: Error)] = []
    private var started: [AppModule] = []

    public init() {}

    public func register(_ module: AppModule) {
        modules.append(module)
    }

    /// 逐个启动；某个模块启动失败只记录，不影响其他模块。
    public func startAll() {
        for module in modules {
            do {
                try module.start()
                started.append(module)
            } catch {
                failures.append((id: module.id, error: error))
            }
        }
    }

    /// 只停止成功启动过的模块，顺序与启动相反。
    public func stopAll() {
        for module in started.reversed() {
            module.stop()
        }
        started.removeAll()
    }

    public var menuItems: [NSMenuItem] {
        modules.flatMap(\.menuItems)
    }
}
```

再加一个文件 `Sources/Core/ViewState.swift`:

```swift
import SwiftUI

/// macOS 27 SDK 里 `@State` 是宏，宏插件只随 Xcode 提供（Command Line Tools 里没有）。
/// 直接引用底层的属性包装器类型可以绕开：在 View 里写 `@ViewState private var x = false`。
public typealias ViewState<Value> = SwiftUI.State<Value>
```

- [ ] **Step 6: 写可执行 Target 的三个文件**

`Sources/MyKit/main.swift`:

```swift
import AppKit

// 顶层代码运行在主线程，但 Swift 5 语言模式下编译器不把它视为 MainActor 隔离，需要显式声明。
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()   // 不会返回，delegate 在整个运行期间保持存活
}
```

`Sources/MyKit/StatusBarController.swift`:

```swift
import AppKit

/// 屏幕右上角的 MyKit 图标。给 NSStatusItem 设置 menu 后，系统对左键和右键都会弹出同一个菜单。
@MainActor
final class StatusBarController: NSObject {
    enum IconState { case normal, paused, warning }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onOpenSettings: () -> Void

    init(moduleMenuItems: [NSMenuItem], onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        super.init()

        let menu = NSMenu()
        for moduleItem in moduleMenuItems {
            menu.addItem(moduleItem)
        }
        if !moduleMenuItems.isEmpty {
            menu.addItem(.separator())
        }
        let settings = NSMenuItem(title: "偏好设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 MyKit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        setIcon(.normal)
    }

    func setIcon(_ state: IconState) {
        let symbol = state == .warning ? "exclamationmark.triangle" : "square.stack.3d.up"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MyKit")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.appearsDisabled = (state == .paused)
    }

    @objc private func openSettings() {
        onOpenSettings()
    }
}
```

`Sources/MyKit/AppDelegate.swift`:

```swift
import AppKit
import Core
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.imiros.mykit", category: "app")
    private let registry = ModuleRegistry()
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        registry.startAll()
        for failure in registry.failures {
            log.error("模块 \(failure.id, privacy: .public) 启动失败: \(String(describing: failure.error), privacy: .public)")
        }
        statusBar = StatusBarController(moduleMenuItems: registry.menuItems, onOpenSettings: {})
        log.info("MyKit 已启动")
    }

    func applicationWillTerminate(_ notification: Notification) {
        registry.stopAll()
    }
}
```

- [ ] **Step 7: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 4 tests in 1 suite passed`

- [ ] **Step 8: 写 `Resources/Info.plist`**

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
</dict>
</plist>
```

- [ ] **Step 9: 写 `scripts/make-icon.swift`**

```swift
// 生成 MyKit 的应用图标。用法：swift scripts/make-icon.swift <输出目录.iconset>
import AppKit

let out = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.96, alpha: 1),
               ending: NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.62, alpha: 1))!.draw(in: path, angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = symbol.size
        symbol.draw(in: NSRect(x: (s - size.width) / 2, y: (s - size.height) / 2, width: size.width, height: size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    try render(px).write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
```

- [ ] **Step 10: 写 `scripts/create-dev-cert.sh`**

```bash
#!/bin/bash
# 一次性操作：创建自签名代码签名证书 "MyKit Dev"，放进专用钥匙串。
# 固定证书签名 → 每次重新编译后，"辅助功能"授权依然有效。
set -euo pipefail

KEYCHAIN="$HOME/Library/Keychains/mykit-dev.keychain-db"
KEYCHAIN_PASSWORD="mykit-dev"
IDENTITY="MyKit Dev"

if [[ -f "$KEYCHAIN" ]]; then
  echo "签名证书已存在：$KEYCHAIN（无需重复创建）"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.conf" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/identity.p12" -name "$IDENTITY" -passout "pass:$KEYCHAIN_PASSWORD"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"   # 不自动上锁
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$KEYCHAIN_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

echo "已创建签名证书 \"$IDENTITY\" → $KEYCHAIN"
```

- [ ] **Step 11: 写 `scripts/build-app.sh` 和 `scripts/install.sh`**

`scripts/build-app.sh`:

```bash
#!/bin/bash
# 编译 release → 组装 build/MyKit.app → 用固定证书签名
set -euo pipefail
cd "$(dirname "$0")/.."

KEYCHAIN="$HOME/Library/Keychains/mykit-dev.keychain-db"
KEYCHAIN_PASSWORD="mykit-dev"
IDENTITY="MyKit Dev"
APP="build/MyKit.app"

if [[ ! -f "$KEYCHAIN" ]]; then
  echo "error: 未找到签名证书，请先运行 scripts/create-dev-cert.sh" >&2
  exit 1
fi

swift build -c release --build-system native

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MyKit "$APP/Contents/MacOS/MyKit"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [[ ! -f build/AppIcon.icns ]]; then
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
codesign --force --keychain "$KEYCHAIN" -s "$IDENTITY" --identifier com.imiros.mykit "$APP"
codesign --verify --strict "$APP"
codesign -d -r- "$APP" 2>&1 | grep '^designated'

echo "完成：$APP"
```

`scripts/install.sh`:

```bash
#!/bin/bash
# 把 build/MyKit.app 安装到 /Applications 并启动
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -d build/MyKit.app ]]; then
  echo "error: 还没有构建，请先运行 scripts/build-app.sh" >&2
  exit 1
fi

pkill -x MyKit || true
sleep 1
rm -rf /Applications/MyKit.app
cp -R build/MyKit.app /Applications/MyKit.app
open /Applications/MyKit.app
echo "已安装并启动：/Applications/MyKit.app（看屏幕右上角的图标）"
```

Run: `chmod +x scripts/create-dev-cert.sh scripts/build-app.sh scripts/install.sh`

- [ ] **Step 12: 创建证书、构建、验证签名稳定**

Run:

```bash
scripts/create-dev-cert.sh
mkdir -p build
scripts/build-app.sh | tee build/sign-1.txt
touch Sources/MyKit/main.swift
scripts/build-app.sh | tee build/sign-2.txt
diff <(grep '^designated' build/sign-1.txt) <(grep '^designated' build/sign-2.txt) && echo "签名身份稳定"
```

Expected: 两次都输出形如 `designated => identifier "com.imiros.mykit" and certificate leaf = H"…"` 的一行，最后打印 `签名身份稳定`。全程不应弹出要求输入密码的对话框。

- [ ] **Step 13: 启动冒烟测试**

Run:

```bash
open build/MyKit.app
sleep 2
pgrep -x MyKit && echo "进程在运行"
/usr/bin/log show --last 1m --predicate 'subsystem == "com.imiros.mykit"' --info | grep "MyKit 已启动"
pkill -x MyKit
```

Expected: 打印进程号和 `进程在运行`；日志里有 `MyKit 已启动`；Dock 里**没有** MyKit 图标。
（人工确认项，留到 Task 7 验收清单第 9 条：右上角出现图标，左键 / 右键都弹出菜单，点"退出 MyKit"后图标消失。）

- [ ] **Step 14: Commit**

```bash
git add .gitignore Package.swift Resources scripts Sources Tests
git commit -m "feat: runnable menu bar skeleton with quit menu, build and signing scripts"
```

---

### Task 2: 双击 Option 检测（纯逻辑）

**Files:**
- Create: `Sources/Core/DoubleTapDetector.swift`, `Sources/Core/ModifierEventTranslator.swift`
- Test: `Tests/CoreTests/DoubleTapDetectorTests.swift`, `Tests/CoreTests/ModifierEventTranslatorTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `public struct DoubleTapDetector { public enum Event: Equatable { case targetDown(otherModifiersHeld: Bool), targetUp, otherInput }; public var maxHold: TimeInterval /*0.3*/; public var maxGap: TimeInterval /*0.3*/; public init(); public mutating func handle(_ event: Event, at time: TimeInterval) -> Bool }` —— 返回 `true` 表示"此刻触发了双击"。
  - `public enum ModifierEventTranslator { public static func translate(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> DoubleTapDetector.Event? }`

规则（来自设计文档 §4）：一次有效轻按 = Option 单独按下 → 松开，按住 ≤ 0.3s，期间无其他按键；第一次松开到第二次按下 ≤ 0.3s，**在第二次按下的瞬间触发**；任何其他按键 / 其他修饰键 / 超时都重置；左右 Option 都算。

- [ ] **Step 1: 写失败的测试 `Tests/CoreTests/DoubleTapDetectorTests.swift`**

```swift
import Foundation
import Testing
@testable import Core

@Suite struct DoubleTapDetectorTests {
    private typealias Event = DoubleTapDetector.Event
    private let down = Event.targetDown(otherModifiersHeld: false)
    private let downWithOthers = Event.targetDown(otherModifiersHeld: true)

    private func run(_ events: [(Event, TimeInterval)]) -> [Bool] {
        var detector = DoubleTapDetector()
        var results: [Bool] = []
        for (event, time) in events {
            results.append(detector.handle(event, at: time))
        }
        return results
    }

    @Test func triggersOnSecondPress() {
        #expect(run([(down, 0.00), (.targetUp, 0.08), (down, 0.20)]) == [false, false, true])
    }

    @Test func doesNotTriggerWhenGapTooLong() {
        #expect(run([(down, 0.00), (.targetUp, 0.08), (down, 0.39)]) == [false, false, false])
    }

    @Test func lateSecondPressCountsAsNewFirstTap() {
        let results = run([(down, 0.00), (.targetUp, 0.08), (down, 0.50), (.targetUp, 0.55), (down, 0.65)])
        #expect(results == [false, false, false, false, true])
    }

    @Test func doesNotTriggerWhenFirstHoldTooLong() {
        #expect(run([(down, 0.00), (.targetUp, 0.35), (down, 0.40)]) == [false, false, false])
    }

    @Test func otherKeyBetweenTapsResets() {
        #expect(run([(down, 0.00), (.targetUp, 0.05), (.otherInput, 0.10), (down, 0.15)]) == [false, false, false, false])
    }

    @Test func otherKeyDuringFirstHoldResets() {
        // Option+字母 输入特殊字符
        #expect(run([(down, 0.00), (.otherInput, 0.03), (.targetUp, 0.06), (down, 0.10)]) == [false, false, false, false])
    }

    @Test func otherModifierHeldOnFirstPressIsIgnored() {
        #expect(run([(downWithOthers, 0.00), (.targetUp, 0.05), (down, 0.10)]) == [false, false, false])
    }

    @Test func otherModifierHeldOnSecondPressDoesNotTrigger() {
        #expect(run([(down, 0.00), (.targetUp, 0.05), (downWithOthers, 0.10)]) == [false, false, false])
    }

    @Test func secondOptionKeyPressedWhileFirstHeldResets() {
        #expect(run([(down, 0.00), (down, 0.05), (.targetUp, 0.08), (down, 0.12)]) == [false, false, false, false])
    }

    @Test func resetsAfterTriggerAndCanTriggerAgain() {
        let results = run([
            (down, 0.00), (.targetUp, 0.05), (down, 0.10),      // 第一次双击
            (.targetUp, 0.15),
            (down, 0.20), (.targetUp, 0.25), (down, 0.30),      // 第二次双击
        ])
        #expect(results == [false, false, true, false, false, false, true])
    }

    @Test func thresholdsAreConfigurable() {
        var detector = DoubleTapDetector()
        detector.maxGap = 0.5
        _ = detector.handle(down, at: 0.0)
        _ = detector.handle(.targetUp, at: 0.05)
        #expect(detector.handle(down, at: 0.50) == true)
    }
}
```

- [ ] **Step 2: 写失败的测试 `Tests/CoreTests/ModifierEventTranslatorTests.swift`**

```swift
import CoreGraphics
import Testing
@testable import Core

@Suite struct ModifierEventTranslatorTests {
    private let leftOption: Int64 = 58
    private let rightOption: Int64 = 61
    private let leftCommand: Int64 = 55

    @Test func optionPressedAlone() {
        let event = ModifierEventTranslator.translate(type: .flagsChanged, keyCode: leftOption, flags: [.maskAlternate])
        #expect(event == .targetDown(otherModifiersHeld: false))
    }

    @Test func rightOptionCountsToo() {
        let event = ModifierEventTranslator.translate(type: .flagsChanged, keyCode: rightOption, flags: [.maskAlternate])
        #expect(event == .targetDown(otherModifiersHeld: false))
    }

    @Test func optionPressedWhileCommandHeld() {
        let event = ModifierEventTranslator.translate(type: .flagsChanged, keyCode: leftOption, flags: [.maskAlternate, .maskCommand])
        #expect(event == .targetDown(otherModifiersHeld: true))
    }

    @Test func capsLockDoesNotCountAsOtherModifier() {
        let event = ModifierEventTranslator.translate(type: .flagsChanged, keyCode: leftOption, flags: [.maskAlternate, .maskAlphaShift])
        #expect(event == .targetDown(otherModifiersHeld: false))
    }

    @Test func optionReleased() {
        let event = ModifierEventTranslator.translate(type: .flagsChanged, keyCode: leftOption, flags: [])
        #expect(event == .targetUp)
    }

    @Test func otherModifierChangeIsOtherInput() {
        let event = ModifierEventTranslator.translate(type: .flagsChanged, keyCode: leftCommand, flags: [.maskCommand])
        #expect(event == .otherInput)
    }

    @Test func keyDownIsOtherInput() {
        let event = ModifierEventTranslator.translate(type: .keyDown, keyCode: 0, flags: [])
        #expect(event == .otherInput)
    }

    @Test func unrelatedEventTypesAreIgnored() {
        #expect(ModifierEventTranslator.translate(type: .keyUp, keyCode: 0, flags: []) == nil)
        #expect(ModifierEventTranslator.translate(type: .tapDisabledByTimeout, keyCode: 0, flags: []) == nil)
    }
}
```

- [ ] **Step 3: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'DoubleTapDetector' in scope`

- [ ] **Step 4: 写 `Sources/Core/DoubleTapDetector.swift`**

```swift
import Foundation

/// 判定"双击某个修饰键"的纯状态机。不依赖任何系统 API，时间由调用方传入（秒，单调递增即可）。
public struct DoubleTapDetector {
    public enum Event: Equatable {
        /// 目标修饰键按下；otherModifiersHeld 表示此刻还按着 ⌘ / ⌃ / ⇧
        case targetDown(otherModifiersHeld: Bool)
        case targetUp
        /// 任何其他按键或其他修饰键的变化
        case otherInput
    }

    private enum State {
        case idle
        case firstDown(at: TimeInterval)
        case firstUp(at: TimeInterval)
    }

    /// 单次轻按最长按住时间
    public var maxHold: TimeInterval = 0.3
    /// 第一次松开到第二次按下的最长间隔
    public var maxGap: TimeInterval = 0.3
    private var state: State = .idle

    public init() {}

    /// 返回 true 表示这个事件完成了一次双击。
    public mutating func handle(_ event: Event, at time: TimeInterval) -> Bool {
        switch (state, event) {
        case (_, .otherInput):
            state = .idle
            return false

        case (.idle, .targetDown(let others)):
            state = others ? .idle : .firstDown(at: time)
            return false

        case (.firstDown(let downAt), .targetUp):
            state = (time - downAt <= maxHold) ? .firstUp(at: time) : .idle
            return false

        case (.firstUp(let upAt), .targetDown(let others)):
            if others {
                state = .idle
                return false
            }
            if time - upAt <= maxGap {
                state = .idle
                return true
            }
            state = .firstDown(at: time)   // 太晚了，当作新的第一次轻按
            return false

        case (.firstDown, .targetDown), (.idle, .targetUp), (.firstUp, .targetUp):
            state = .idle
            return false
        }
    }
}
```

- [ ] **Step 5: 写 `Sources/Core/ModifierEventTranslator.swift`**

```swift
import CoreGraphics

/// 把 CGEvent 的原始字段翻译成 DoubleTapDetector 的事件。纯函数，方便测试。
public enum ModifierEventTranslator {
    /// 左 Option = 58，右 Option = 61
    public static let optionKeyCodes: Set<Int64> = [58, 61]
    /// Caps Lock（maskAlphaShift）可能长期亮着，不算"其他修饰键"
    private static let otherModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskShift]

    public static func translate(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> DoubleTapDetector.Event? {
        switch type {
        case .keyDown:
            return .otherInput
        case .flagsChanged:
            guard optionKeyCodes.contains(keyCode) else { return .otherInput }
            if flags.contains(.maskAlternate) {
                return .targetDown(otherModifiersHeld: !flags.intersection(otherModifiers).isEmpty)
            }
            return .targetUp
        default:
            return nil
        }
    }
}
```

- [ ] **Step 6: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: 全部通过（Task 1 的 4 个 + 本任务 19 个）。

- [ ] **Step 7: Commit**

```bash
git add Sources/Core/DoubleTapDetector.swift Sources/Core/ModifierEventTranslator.swift Tests/CoreTests
git commit -m "feat: double-tap modifier detector and CGEvent translator"
```

---

### Task 3: 剪切板存储（SQLite + FTS5）

**Files:**
- Modify: `Package.swift`（加入 `ClipboardModule` 与其测试 Target）
- Create: `Sources/ClipboardModule/SQLiteDatabase.swift`, `Sources/ClipboardModule/ClipboardItem.swift`, `Sources/ClipboardModule/ClipboardStore.swift`
- Test: `Tests/ClipboardModuleTests/ClipboardStoreTests.swift`, `Tests/ClipboardModuleTests/ClipboardItemTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `public struct ClipboardItem: Identifiable, Equatable, Sendable { public let id: Int64; public let text: String; public let appBundleID: String?; public let appName: String?; public let createdAt: Date; public let lastUsedAt: Date; public var summary: String }`
  - `public actor ClipboardStore`：
    - `public enum Location { case inMemory; case file(URL) }`
    - `public init(location: Location) throws`
    - `public static func openRecovering(at url: URL, now: Date = Date()) throws -> (store: ClipboardStore, recovered: Bool)`
    - `@discardableResult public func add(text: String, appBundleID: String?, appName: String?, at date: Date = Date()) throws -> Int64`
    - `@discardableResult public func touch(text: String, at date: Date = Date()) throws -> Bool`
    - `public func search(query: String, limit: Int, offset: Int) throws -> [ClipboardItem]`
    - `public func delete(id: Int64) throws`
    - `public func clearAll() throws`
    - `@discardableResult public func purge(olderThan cutoff: Date) throws -> Int`
    - `public func count() throws -> Int`

- [ ] **Step 1: 更新 `Package.swift`（完整内容）**

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
        .executableTarget(name: "MyKit", dependencies: ["Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "ClipboardModuleTests", dependencies: ["ClipboardModule"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: 写失败的测试 `Tests/ClipboardModuleTests/ClipboardStoreTests.swift`**

```swift
import Foundation
import Testing
@testable import ClipboardModule

@Suite struct ClipboardStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore() throws -> ClipboardStore {
        try ClipboardStore(location: .inMemory)
    }

    @Test func addThenSearchReturnsItemWithAllFields() async throws {
        let store = try makeStore()
        let id = try await store.add(text: "hello world", appBundleID: "com.apple.Safari", appName: "Safari", at: t0)

        let items = try await store.search(query: "", limit: 10, offset: 0)

        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.id == id)
        #expect(item.text == "hello world")
        #expect(item.appBundleID == "com.apple.Safari")
        #expect(item.appName == "Safari")
        #expect(item.createdAt == t0)
        #expect(item.lastUsedAt == t0)
    }

    @Test func emptyQueryReturnsNewestFirst() async throws {
        let store = try makeStore()
        try await store.add(text: "old", appBundleID: nil, appName: nil, at: t0)
        try await store.add(text: "new", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(10))

        let items = try await store.search(query: "", limit: 10, offset: 0)

        #expect(items.map(\.text) == ["new", "old"])
    }

    @Test func duplicateTextMovesToTopInsteadOfInserting() async throws {
        let store = try makeStore()
        let firstID = try await store.add(text: "dup", appBundleID: "a", appName: "A", at: t0)
        try await store.add(text: "other", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(5))
        let secondID = try await store.add(text: "dup", appBundleID: "b", appName: "B", at: t0.addingTimeInterval(10))

        let items = try await store.search(query: "", limit: 10, offset: 0)

        #expect(secondID == firstID)
        #expect(items.map(\.text) == ["dup", "other"])
        #expect(items[0].createdAt == t0)
        #expect(items[0].lastUsedAt == t0.addingTimeInterval(10))
        #expect(items[0].appName == "B")   // 来源更新为最近一次复制的 App
    }

    @Test func touchMovesExistingToTopAndKeepsSourceApp() async throws {
        let store = try makeStore()
        try await store.add(text: "first", appBundleID: "a", appName: "A", at: t0)
        try await store.add(text: "second", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(5))

        let touched = try await store.touch(text: "first", at: t0.addingTimeInterval(10))
        let items = try await store.search(query: "", limit: 10, offset: 0)

        #expect(touched)
        #expect(items.map(\.text) == ["first", "second"])
        #expect(items[0].appName == "A")
    }

    @Test func touchUnknownTextReturnsFalseAndInsertsNothing() async throws {
        let store = try makeStore()
        let touched = try await store.touch(text: "ghost", at: t0)
        #expect(!touched)
        #expect(try await store.count() == 0)
    }

    @Test func ftsSearchMatchesSubstringCaseInsensitively() async throws {
        let store = try makeStore()
        try await store.add(text: "git rebase -i HEAD~3", appBundleID: nil, appName: nil, at: t0)
        try await store.add(text: "SELECT * FROM users", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(1))

        #expect(try await store.search(query: "REBASE", limit: 10, offset: 0).map(\.text) == ["git rebase -i HEAD~3"])
        #expect(try await store.search(query: "from use", limit: 10, offset: 0).map(\.text) == ["SELECT * FROM users"])
    }

    @Test func chineseSubstringSearch() async throws {
        let store = try makeStore()
        try await store.add(text: "北京亚太宏图科技有限公司", appBundleID: nil, appName: nil, at: t0)
        try await store.add(text: "上海某某公司", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(1))

        #expect(try await store.search(query: "亚太宏图", limit: 10, offset: 0).count == 1)   // ≥3 字符走 FTS
        #expect(try await store.search(query: "公司", limit: 10, offset: 0).count == 2)       // 2 字符走 LIKE
        #expect(try await store.search(query: "京", limit: 10, offset: 0).count == 1)         // 1 字符走 LIKE
    }

    @Test func shortQueryTreatsLikeWildcardsLiterally() async throws {
        let store = try makeStore()
        try await store.add(text: "100% sure", appBundleID: nil, appName: nil, at: t0)
        try await store.add(text: "a_b", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(1))
        try await store.add(text: "plain", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(2))

        #expect(try await store.search(query: "%", limit: 10, offset: 0).map(\.text) == ["100% sure"])
        #expect(try await store.search(query: "_", limit: 10, offset: 0).map(\.text) == ["a_b"])
    }

    @Test func ftsSpecialCharactersDoNotThrow() async throws {
        let store = try makeStore()
        try await store.add(text: "say \"hello\" * now", appBundleID: nil, appName: nil, at: t0)

        #expect(try await store.search(query: "\"hello\"", limit: 10, offset: 0).count == 1)
        #expect(try await store.search(query: "* now", limit: 10, offset: 0).count == 1)
        #expect(try await store.search(query: "AND OR NOT", limit: 10, offset: 0).isEmpty)
    }

    @Test func queryIsTrimmedBeforeSearching() async throws {
        let store = try makeStore()
        try await store.add(text: "hello", appBundleID: nil, appName: nil, at: t0)
        #expect(try await store.search(query: "   ", limit: 10, offset: 0).count == 1)
        #expect(try await store.search(query: " hello ", limit: 10, offset: 0).count == 1)
    }

    @Test func paginationWithLimitAndOffset() async throws {
        let store = try makeStore()
        for i in 0..<5 {
            try await store.add(text: "item \(i)", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(Double(i)))
        }

        let page1 = try await store.search(query: "", limit: 2, offset: 0)
        let page2 = try await store.search(query: "", limit: 2, offset: 2)
        let page3 = try await store.search(query: "", limit: 2, offset: 4)

        #expect(page1.map(\.text) == ["item 4", "item 3"])
        #expect(page2.map(\.text) == ["item 2", "item 1"])
        #expect(page3.map(\.text) == ["item 0"])
    }

    @Test func deleteRemovesItemFromListAndFromFTS() async throws {
        let store = try makeStore()
        let id = try await store.add(text: "delete me please", appBundleID: nil, appName: nil, at: t0)

        try await store.delete(id: id)

        #expect(try await store.count() == 0)
        #expect(try await store.search(query: "delete me", limit: 10, offset: 0).isEmpty)
    }

    @Test func purgeRemovesOnlyItemsLastUsedBeforeCutoff() async throws {
        let store = try makeStore()
        try await store.add(text: "expired", appBundleID: nil, appName: nil, at: t0)
        try await store.add(text: "reused", appBundleID: nil, appName: nil, at: t0)
        try await store.add(text: "fresh", appBundleID: nil, appName: nil, at: t0.addingTimeInterval(8 * 86400))
        try await store.touch(text: "reused", at: t0.addingTimeInterval(8 * 86400))

        let removed = try await store.purge(olderThan: t0.addingTimeInterval(86400))

        #expect(removed == 1)
        let remaining = try await store.search(query: "", limit: 10, offset: 0).map(\.text)
        #expect(Set(remaining) == ["reused", "fresh"])
    }

    @Test func clearAllRemovesEverything() async throws {
        let store = try makeStore()
        try await store.add(text: "one two three", appBundleID: nil, appName: nil, at: t0)
        try await store.clearAll()
        #expect(try await store.count() == 0)
        #expect(try await store.search(query: "two", limit: 10, offset: 0).isEmpty)
    }

    @Test func fileStorePersistsAcrossReopen() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mykit-test-\(UUID().uuidString)")
            .appendingPathComponent("clipboard.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let opened = try ClipboardStore.openRecovering(at: url)
            #expect(!opened.recovered)
            try await opened.store.add(text: "persisted", appBundleID: nil, appName: nil, at: t0)
        }
        let reopened = try ClipboardStore.openRecovering(at: url)

        #expect(!reopened.recovered)
        #expect(try await reopened.store.search(query: "", limit: 10, offset: 0).map(\.text) == ["persisted"])
    }

    @Test func corruptFileIsBackedUpAndRecreated() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mykit-test-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("clipboard.sqlite")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(repeating: 0x41, count: 4096).write(to: url)

        let opened = try ClipboardStore.openRecovering(at: url, now: t0)

        #expect(opened.recovered)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("clipboard.sqlite.corrupt-1800000000").path))
        try await opened.store.add(text: "works again", appBundleID: nil, appName: nil, at: t0)
        #expect(try await opened.store.count() == 1)
    }
}
```

- [ ] **Step 3: 写失败的测试 `Tests/ClipboardModuleTests/ClipboardItemTests.swift`**

```swift
import Foundation
import Testing
@testable import ClipboardModule

@Suite struct ClipboardItemTests {
    private func item(_ text: String) -> ClipboardItem {
        ClipboardItem(id: 1, text: text, appBundleID: nil, appName: nil, createdAt: Date(), lastUsedAt: Date())
    }

    @Test func summaryCollapsesWhitespaceAndNewlines() {
        #expect(item("  line one\n\n\tline   two  ").summary == "line one line two")
    }

    @Test func summaryTruncatesLongText() {
        let summary = item(String(repeating: "a", count: 500)).summary
        #expect(summary.count == 121)            // 120 个字符 + "…"
        #expect(summary.hasSuffix("…"))
    }

    @Test func shortTextIsNotTruncated() {
        #expect(item("短文本").summary == "短文本")
    }
}
```

- [ ] **Step 4: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败（`ClipboardModule` 没有源文件 / `cannot find 'ClipboardStore' in scope`）

- [ ] **Step 5: 写 `Sources/ClipboardModule/SQLiteDatabase.swift`**

```swift
import Foundation
import SQLite3

struct SQLiteError: Error, CustomStringConvertible {
    let code: Int32
    let message: String
    var description: String { "SQLite error \(code): \(message)" }
}

enum SQLiteValue {
    case text(String)
    case double(Double)
    case int(Int64)
    case null
}

/// 查询结果的一行。只在 query 的 map 闭包内有效。
struct SQLiteRow {
    fileprivate let statement: OpaquePointer

    func string(_ index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }

    func int64(_ index: Int32) -> Int64 {
        sqlite3_column_int64(statement, index)
    }

    func double(_ index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite3 C API 的最小包装。本身不做线程同步，由持有它的 actor 保证串行访问。
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close_v2(handle)
            handle = nil
            throw SQLiteError(code: rc, message: message)
        }
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    var lastInsertRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    /// 执行一段不带参数的 SQL（可含多条语句），用于建表。
    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if rc != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(errorMessage)
            throw SQLiteError(code: rc, message: message)
        }
    }

    /// 执行一条带参数的写语句，返回受影响的行数。
    @discardableResult
    func run(_ sql: String, _ params: [SQLiteValue] = []) throws -> Int {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        let rc = sqlite3_step(statement)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw lastError(rc) }
        return Int(sqlite3_changes(handle))
    }

    func query<T>(_ sql: String, _ params: [SQLiteValue] = [], map: (SQLiteRow) -> T) throws -> [T] {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        var rows: [T] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_ROW {
                rows.append(map(SQLiteRow(statement: statement)))
            } else if rc == SQLITE_DONE {
                return rows
            } else {
                throw lastError(rc)
            }
        }
    }

    private func prepare(_ sql: String, _ params: [SQLiteValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard rc == SQLITE_OK, let statement else { throw lastError(rc) }
        for (offset, param) in params.enumerated() {
            let index = Int32(offset + 1)
            let bindResult: Int32
            switch param {
            case .text(let value): bindResult = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            case .double(let value): bindResult = sqlite3_bind_double(statement, index, value)
            case .int(let value): bindResult = sqlite3_bind_int64(statement, index, value)
            case .null: bindResult = sqlite3_bind_null(statement, index)
            }
            guard bindResult == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw lastError(bindResult)
            }
        }
        return statement
    }

    private func lastError(_ code: Int32) -> SQLiteError {
        SQLiteError(code: code, message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown")
    }
}
```

- [ ] **Step 6: 写 `Sources/ClipboardModule/ClipboardItem.swift`**

```swift
import Foundation

public struct ClipboardItem: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let text: String
    public let appBundleID: String?
    public let appName: String?
    /// 第一次复制的时间
    public let createdAt: Date
    /// 最近一次复制 / 粘贴的时间，列表按它倒序
    public let lastUsedAt: Date

    public init(id: Int64, text: String, appBundleID: String?, appName: String?, createdAt: Date, lastUsedAt: Date) {
        self.id = id
        self.text = text
        self.appBundleID = appBundleID
        self.appName = appName
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    /// 列表里显示的单行摘要：压缩空白，最多 120 个字符。
    public var summary: String {
        let head = text.prefix(600)   // 先截一段，避免对 1MB 文本做整体处理
        let collapsed = head.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if collapsed.count > 120 {
            return String(collapsed.prefix(120)) + "…"
        }
        return collapsed
    }
}
```

- [ ] **Step 7: 写 `Sources/ClipboardModule/ClipboardStore.swift`**

```swift
import CryptoKit
import Foundation

/// 剪切板历史的持久化。actor 保证所有数据库访问串行执行。
public actor ClipboardStore {
    public enum Location {
        case inMemory
        case file(URL)
    }

    private let db: SQLiteDatabase

    public init(location: Location) throws {
        switch location {
        case .inMemory:
            db = try SQLiteDatabase(path: ":memory:")
        case .file(let url):
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            db = try SQLiteDatabase(path: url.path)
        }
        try Self.migrate(db)
    }

    /// 打开数据库；打不开（文件损坏）时把旧文件改名备份并新建。recovered 为 true 表示发生过重建。
    public static func openRecovering(at url: URL, now: Date = Date()) throws -> (store: ClipboardStore, recovered: Bool) {
        do {
            return (try ClipboardStore(location: .file(url)), false)
        } catch {
            let fileManager = FileManager.default
            let backupName = "\(url.lastPathComponent).corrupt-\(Int(now.timeIntervalSince1970))"
            let backup = url.deletingLastPathComponent().appendingPathComponent(backupName)
            try? fileManager.moveItem(at: url, to: backup)
            for suffix in ["-wal", "-shm"] {
                try? fileManager.removeItem(atPath: url.path + suffix)
            }
            return (try ClipboardStore(location: .file(url)), true)
        }
    }

    private static func migrate(_ db: SQLiteDatabase) throws {
        try db.execute("""
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS items (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            text         TEXT NOT NULL,
            text_hash    TEXT NOT NULL UNIQUE,
            app_bundle   TEXT,
            app_name     TEXT,
            created_at   REAL NOT NULL,
            last_used_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_items_last_used ON items(last_used_at DESC);
        CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
            text, content='items', content_rowid='id', tokenize='trigram'
        );
        CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
            INSERT INTO items_fts(rowid, text) VALUES (new.id, new.text);
        END;
        CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
            INSERT INTO items_fts(items_fts, rowid, text) VALUES ('delete', old.id, old.text);
        END;
        CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE OF text ON items BEGIN
            INSERT INTO items_fts(items_fts, rowid, text) VALUES ('delete', old.id, old.text);
            INSERT INTO items_fts(rowid, text) VALUES (new.id, new.text);
        END;
        """)
    }

    /// 新文本 → 插入；已存在的文本 → 只更新时间和来源 App（移到最前）。返回记录 id。
    @discardableResult
    public func add(text: String, appBundleID: String?, appName: String?, at date: Date = Date()) throws -> Int64 {
        let hash = Self.hash(text)
        let timestamp = date.timeIntervalSince1970
        let existing = try db.query("SELECT id FROM items WHERE text_hash = ?", [.text(hash)]) { $0.int64(0) }
        if let id = existing.first {
            try db.run(
                "UPDATE items SET last_used_at = ?, app_bundle = ?, app_name = ? WHERE id = ?",
                [.double(timestamp), Self.optional(appBundleID), Self.optional(appName), .int(id)]
            )
            return id
        }
        try db.run(
            "INSERT INTO items (text, text_hash, app_bundle, app_name, created_at, last_used_at) VALUES (?, ?, ?, ?, ?, ?)",
            [.text(text), .text(hash), Self.optional(appBundleID), Self.optional(appName), .double(timestamp), .double(timestamp)]
        )
        return db.lastInsertRowID
    }

    /// 只把已有记录移到最前（MyKit 自己粘贴时用）。记录不存在返回 false，不会插入。
    @discardableResult
    public func touch(text: String, at date: Date = Date()) throws -> Bool {
        let changed = try db.run(
            "UPDATE items SET last_used_at = ? WHERE text_hash = ?",
            [.double(date.timeIntervalSince1970), .text(Self.hash(text))]
        )
        return changed > 0
    }

    /// 空查询 → 全部；≥3 个字符 → FTS5 trigram；1–2 个字符 → LIKE。一律按最近使用时间倒序。
    public func search(query: String, limit: Int, offset: Int) throws -> [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let columns = "id, text, app_bundle, app_name, created_at, last_used_at"
        let order = "ORDER BY last_used_at DESC, id DESC LIMIT ? OFFSET ?"
        let paging: [SQLiteValue] = [.int(Int64(limit)), .int(Int64(offset))]

        if trimmed.isEmpty {
            return try db.query("SELECT \(columns) FROM items \(order)", paging, map: Self.item)
        }
        if trimmed.count >= 3 {
            let phrase = "\"" + trimmed.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            return try db.query(
                "SELECT \(columns) FROM items WHERE id IN (SELECT rowid FROM items_fts WHERE items_fts MATCH ?) \(order)",
                [.text(phrase)] + paging,
                map: Self.item
            )
        }
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return try db.query(
            "SELECT \(columns) FROM items WHERE text LIKE ? ESCAPE '\\' \(order)",
            [.text("%\(escaped)%")] + paging,
            map: Self.item
        )
    }

    public func delete(id: Int64) throws {
        try db.run("DELETE FROM items WHERE id = ?", [.int(id)])
    }

    public func clearAll() throws {
        try db.run("DELETE FROM items")
    }

    /// 删除最近使用时间早于 cutoff 的记录，返回删除条数。
    @discardableResult
    public func purge(olderThan cutoff: Date) throws -> Int {
        try db.run("DELETE FROM items WHERE last_used_at < ?", [.double(cutoff.timeIntervalSince1970)])
    }

    public func count() throws -> Int {
        let rows = try db.query("SELECT COUNT(*) FROM items") { Int($0.int64(0)) }
        return rows.first ?? 0
    }

    private static func item(_ row: SQLiteRow) -> ClipboardItem {
        ClipboardItem(
            id: row.int64(0),
            text: row.string(1) ?? "",
            appBundleID: row.string(2),
            appName: row.string(3),
            createdAt: Date(timeIntervalSince1970: row.double(4)),
            lastUsedAt: Date(timeIntervalSince1970: row.double(5))
        )
    }

    private static func optional(_ value: String?) -> SQLiteValue {
        value.map(SQLiteValue.text) ?? .null
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 8: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: 全部通过。如果 `corruptFileIsBackedUpAndRecreated` 失败且提示 init 没抛错，说明垃圾文件被 SQLite 延迟到首次读写才报错 —— `migrate` 里的 `PRAGMA journal_mode = WAL` 就是第一次读写，应当抛 `SQLITE_NOTADB (26)`；检查 `migrate` 是否确实在 `init` 里被调用。

- [ ] **Step 9: Commit**

```bash
git add Package.swift Sources/ClipboardModule Tests/ClipboardModuleTests
git commit -m "feat: clipboard store on SQLite with FTS5 trigram search, dedupe, purge and corruption recovery"
```

---

### Task 4: 剪切板监听（过滤规则 + 轮询入库）

**Files:**
- Create: `Sources/ClipboardModule/CaptureFilter.swift`, `Sources/ClipboardModule/ClipboardSettings.swift`, `Sources/ClipboardModule/ClipboardMonitor.swift`
- Test: `Tests/ClipboardModuleTests/CaptureFilterTests.swift`, `Tests/ClipboardModuleTests/ClipboardSettingsTests.swift`, `Tests/ClipboardModuleTests/ClipboardMonitorTests.swift`

**Interfaces:**
- Consumes: `ClipboardStore.add(text:appBundleID:appName:at:)`、`ClipboardStore.touch(text:at:)`（Task 3）
- Produces:
  - `public enum CaptureDecision: Equatable { case record(String), touchOwn(String), skip }`
  - `public enum CaptureFilter { public static let ownWriteType = "com.imiros.mykit.own-write"; public static let maxBytes = 1_048_576; public static func decide(types: [String], string: String?) -> CaptureDecision }`
  - `public struct ClipboardSettings { public static let retentionDaysKey = "clipboard.retentionDays"; public static let defaultRetentionDays = 7; public init(defaults: UserDefaults = .standard); public var retentionDays: Int { get nonmutating set } }`（读取时夹在 1…90，未设置时为 7）
  - `public protocol PasteboardReading: AnyObject { var changeCount: Int { get }; func currentTypeIdentifiers() -> [String]; func currentString() -> String? }`，`NSPasteboard` 已遵循
  - `@MainActor public final class ClipboardMonitor { public var isPaused: Bool; public init(pasteboard: PasteboardReading, store: ClipboardStore, frontmostApp: @escaping () -> (bundleID: String?, name: String?) = …, now: @escaping () -> Date = Date.init); public func start(interval: TimeInterval = 0.5); public func stop(); public func poll() async }`

- [ ] **Step 1: 写失败的测试 `Tests/ClipboardModuleTests/CaptureFilterTests.swift`**

```swift
import Testing
@testable import ClipboardModule

@Suite struct CaptureFilterTests {
    private let plain = ["public.utf8-plain-text"]

    @Test func recordsPlainText() {
        #expect(CaptureFilter.decide(types: plain, string: "hello") == .record("hello"))
    }

    @Test func keepsOriginalTextIncludingSurroundingWhitespace() {
        #expect(CaptureFilter.decide(types: plain, string: "  indented\n") == .record("  indented\n"))
    }

    @Test func skipsWhenNoString() {
        #expect(CaptureFilter.decide(types: ["public.png"], string: nil) == .skip)
    }

    @Test func skipsBlankText() {
        #expect(CaptureFilter.decide(types: plain, string: " \n\t ") == .skip)
        #expect(CaptureFilter.decide(types: plain, string: "") == .skip)
    }

    @Test func skipsConcealedContentFromPasswordManagers() {
        let types = plain + ["org.nspasteboard.ConcealedType"]
        #expect(CaptureFilter.decide(types: types, string: "hunter2") == .skip)
    }

    @Test func skipsTransientContent() {
        let types = plain + ["org.nspasteboard.TransientType"]
        #expect(CaptureFilter.decide(types: types, string: "temp") == .skip)
    }

    @Test func skipsTextLargerThanOneMegabyte() {
        let big = String(repeating: "a", count: CaptureFilter.maxBytes + 1)
        #expect(CaptureFilter.decide(types: plain, string: big) == .skip)
    }

    @Test func acceptsTextExactlyAtLimit() {
        let atLimit = String(repeating: "a", count: CaptureFilter.maxBytes)
        #expect(CaptureFilter.decide(types: plain, string: atLimit) == .record(atLimit))
    }

    @Test func sizeLimitCountsUTF8BytesNotCharacters() {
        let chinese = String(repeating: "中", count: CaptureFilter.maxBytes / 3 + 1)   // 每个字 3 字节
        #expect(CaptureFilter.decide(types: plain, string: chinese) == .skip)
    }

    @Test func recognisesOwnWrites() {
        let types = plain + [CaptureFilter.ownWriteType]
        #expect(CaptureFilter.decide(types: types, string: "pasted by MyKit") == .touchOwn("pasted by MyKit"))
    }

    @Test func concealedWinsOverOwnWrite() {
        let types = plain + [CaptureFilter.ownWriteType, "org.nspasteboard.ConcealedType"]
        #expect(CaptureFilter.decide(types: types, string: "x") == .skip)
    }
}
```

- [ ] **Step 2: 写失败的测试 `Tests/ClipboardModuleTests/ClipboardSettingsTests.swift`**

```swift
import Foundation
import Testing
@testable import ClipboardModule

@Suite struct ClipboardSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsToSevenDays() {
        #expect(ClipboardSettings(defaults: makeDefaults()).retentionDays == 7)
    }

    @Test func storesAndReadsValue() {
        let defaults = makeDefaults()
        ClipboardSettings(defaults: defaults).retentionDays = 30
        #expect(ClipboardSettings(defaults: defaults).retentionDays == 30)
        #expect(defaults.integer(forKey: ClipboardSettings.retentionDaysKey) == 30)
    }

    @Test func clampsOutOfRangeValues() {
        let defaults = makeDefaults()
        defaults.set(500, forKey: ClipboardSettings.retentionDaysKey)
        #expect(ClipboardSettings(defaults: defaults).retentionDays == 90)
        defaults.set(-3, forKey: ClipboardSettings.retentionDaysKey)
        #expect(ClipboardSettings(defaults: defaults).retentionDays == 1)
    }
}
```

- [ ] **Step 3: 写失败的测试 `Tests/ClipboardModuleTests/ClipboardMonitorTests.swift`**

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

- [ ] **Step 4: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'CaptureFilter' in scope`

- [ ] **Step 5: 写 `Sources/ClipboardModule/CaptureFilter.swift`**

```swift
import Foundation

public enum CaptureDecision: Equatable {
    /// 记录这段文本
    case record(String)
    /// 这是 MyKit 自己写入的（用户刚从面板粘贴）：只把已有记录移到最前
    case touchOwn(String)
    case skip
}

/// 决定一次剪切板变化要不要进历史。纯函数。
public enum CaptureFilter {
    public static let ownWriteType = "com.imiros.mykit.own-write"
    public static let maxBytes = 1_048_576
    /// 密码管理器等按 nspasteboard.org 约定打的标记
    private static let ignoredTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
    ]

    public static func decide(types: [String], string: String?) -> CaptureDecision {
        if types.contains(where: ignoredTypes.contains) { return .skip }
        guard let string else { return .skip }
        if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .skip }
        if string.utf8.count > maxBytes { return .skip }
        if types.contains(ownWriteType) { return .touchOwn(string) }
        return .record(string)
    }
}
```

- [ ] **Step 6: 写 `Sources/ClipboardModule/ClipboardSettings.swift`**

```swift
import Foundation

public struct ClipboardSettings {
    public static let retentionDaysKey = "clipboard.retentionDays"
    public static let defaultRetentionDays = 7
    public static let retentionRange = 1...90

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 历史保留天数。未设置时为 7；读取时夹在 1…90 之间。
    public var retentionDays: Int {
        get {
            guard defaults.object(forKey: Self.retentionDaysKey) != nil else { return Self.defaultRetentionDays }
            let stored = defaults.integer(forKey: Self.retentionDaysKey)
            return min(max(stored, Self.retentionRange.lowerBound), Self.retentionRange.upperBound)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Self.retentionDaysKey)
        }
    }
}
```

- [ ] **Step 7: 写 `Sources/ClipboardModule/ClipboardMonitor.swift`**

```swift
import AppKit
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

        let decision = CaptureFilter.decide(
            types: pasteboard.currentTypeIdentifiers(),
            string: pasteboard.currentString()
        )
        do {
            switch decision {
            case .record(let text):
                let app = frontmostApp()
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

- [ ] **Step 8: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: 全部通过。

- [ ] **Step 9: Commit**

```bash
git add Sources/ClipboardModule Tests/ClipboardModuleTests
git commit -m "feat: clipboard monitor with capture filter and retention settings"
```

---

### Task 5: Core 系统服务 —— 权限、粘贴、事件监听、浮动面板

**Files:**
- Create: `Sources/Core/Permissions.swift`, `Sources/Core/PasteService.swift`, `Sources/Core/ModifierEventTap.swift`, `Sources/Core/FloatingPanel.swift`
- Test: `Tests/CoreTests/AccessibilityWatcherTests.swift`, `Tests/CoreTests/PasteServiceTests.swift`, `Tests/CoreTests/FloatingPanelTests.swift`

**Interfaces:**
- Consumes: `DoubleTapDetector`、`ModifierEventTranslator`（Task 2）
- Produces:
  - `public enum Permissions { static var isAccessibilityTrusted: Bool; static func openAccessibilitySettings(); static var pasteboardNeedsUserApproval: Bool; static func openPrivacySettings() }`
  - `@MainActor public final class AccessibilityWatcher { public var onChange: ((Bool) -> Void)?; public private(set) var isTrusted: Bool; public init(check: @escaping () -> Bool = …); public func start(interval: TimeInterval = 1.0); public func stop(); public func poll() }`
  - `public enum PasteService { static let ownWriteType: NSPasteboard.PasteboardType /* "com.imiros.mykit.own-write" */; static func write(_ text: String, to pasteboard: NSPasteboard = .general); static func sendPasteKeystroke(); static func paste(_ text: String, delay: TimeInterval = 0.05) }`
  - `public final class ModifierEventTap { public var onDoubleTap: (() -> Void)?; public var isRunning: Bool; public init(); @discardableResult public func start() -> Bool; public func stop() }`
  - `public final class FloatingPanel: NSPanel { public var onClose: (() -> Void)?; public var keyHandler: ((NSEvent) -> Bool)?; public init(size: NSSize); public func present<Content: View>(_ view: Content); public var isComposingText: Bool; public static func frame(for size: NSSize, inVisibleFrame visible: NSRect) -> NSRect }`

`ModifierEventTap` 依赖真实的系统事件流和辅助功能授权，无法单元测试；它只是把 Task 2 已测过的两个纯逻辑件接到 `CGEventTap` 上，正确性由 Task 7 的手动验收覆盖。

- [ ] **Step 1: 写失败的测试 `Tests/CoreTests/AccessibilityWatcherTests.swift`**

```swift
import Testing
@testable import Core

@MainActor
@Suite struct AccessibilityWatcherTests {
    @Test func reportsInitialStateWithoutFiringCallback() {
        var changes: [Bool] = []
        let watcher = AccessibilityWatcher(check: { true })
        watcher.onChange = { changes.append($0) }

        watcher.poll()

        #expect(watcher.isTrusted)
        #expect(changes.isEmpty)
    }

    @Test func firesOnlyWhenValueChanges() {
        var trusted = false
        var changes: [Bool] = []
        let watcher = AccessibilityWatcher(check: { trusted })
        watcher.onChange = { changes.append($0) }

        watcher.poll()
        trusted = true
        watcher.poll()
        watcher.poll()
        trusted = false
        watcher.poll()

        #expect(changes == [true, false])
        #expect(!watcher.isTrusted)
    }
}
```

- [ ] **Step 2: 写失败的测试 `Tests/CoreTests/PasteServiceTests.swift`**

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

    @Test func ownWriteTypeMatchesTheSpecIdentifier() {
        #expect(PasteService.ownWriteType.rawValue == "com.imiros.mykit.own-write")
    }
}
```

- [ ] **Step 3: 写失败的测试 `Tests/CoreTests/FloatingPanelTests.swift`**

```swift
import AppKit
import Testing
@testable import Core

@Suite struct FloatingPanelTests {
    @Test func frameIsHorizontallyCenteredAndInUpperPart() {
        let visible = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let frame = FloatingPanel.frame(for: NSSize(width: 760, height: 460), inVisibleFrame: visible)

        #expect(frame.size == NSSize(width: 760, height: 460))
        #expect(frame.midX == visible.midX)
        #expect(frame.maxY == 800)     // 顶边距离可见区域顶部 20%
    }

    @Test func frameRespectsScreenOrigin() {
        // 第二块显示器：原点不在 (0,0)
        let visible = NSRect(x: 1600, y: -200, width: 1200, height: 800)
        let frame = FloatingPanel.frame(for: NSSize(width: 760, height: 460), inVisibleFrame: visible)

        #expect(frame.midX == visible.midX)
        #expect(frame.maxY == visible.maxY - 160)
    }

    @Test func frameStaysInsideSmallScreens() {
        let visible = NSRect(x: 0, y: 0, width: 800, height: 500)
        let frame = FloatingPanel.frame(for: NSSize(width: 760, height: 460), inVisibleFrame: visible)

        #expect(frame.minY >= visible.minY)
        #expect(frame.maxY <= visible.maxY)
    }
}
```

- [ ] **Step 4: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'AccessibilityWatcher' in scope`

- [ ] **Step 5: 写 `Sources/Core/Permissions.swift`**

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

- [ ] **Step 6: 写 `Sources/Core/PasteService.swift`**

```swift
import AppKit
import CoreGraphics

public enum PasteService {
    /// 写入剪切板时附带的标记，剪切板监听据此识别"这是 MyKit 自己写的"。
    public static let ownWriteType = NSPasteboard.PasteboardType("com.imiros.mykit.own-write")

    public static func write(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, ownWriteType], owner: nil)
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("1", forType: ownWriteType)
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

- [ ] **Step 7: 写 `Sources/Core/ModifierEventTap.swift`**

```swift
import CoreGraphics
import Foundation
import os

/// 全局监听键盘事件，检测到双击 Option 时回调。需要"辅助功能"授权。
/// 回调发生在主线程（事件源加在主 RunLoop 上）。
public final class ModifierEventTap {
    public var onDoubleTap: (() -> Void)?

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var detector = DoubleTapDetector()
    private let log = Logger(subsystem: "com.imiros.mykit", category: "hotkey")

    public init() {}

    public var isRunning: Bool { port != nil }

    /// 返回 false 表示创建失败（通常是还没有辅助功能授权）。
    @discardableResult
    public func start() -> Bool {
        if port != nil { return true }

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            if let userInfo {
                let tap = Unmanaged<ModifierEventTap>.fromOpaque(userInfo).takeUnretainedValue()
                tap.handle(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)   // 永远原样放行，不修改也不吞掉事件
        }
        // .defaultTap 只需要"辅助功能"授权；.listenOnly 会额外要求"输入监控"
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

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // 系统会在回调太慢或用户输入安全内容时停用监听，这里立刻重新启用
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return
        }
        let translated = ModifierEventTranslator.translate(
            type: type,
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            flags: event.flags
        )
        guard let translated else { return }
        if detector.handle(translated, at: ProcessInfo.processInfo.systemUptime) {
            onDoubleTap?()
        }
    }
}
```

- [ ] **Step 8: 写 `Sources/Core/FloatingPanel.swift`**

```swift
import AppKit
import SwiftUI

/// 不抢焦点的浮动面板：能接收键盘输入，但不会让 MyKit 变成前台 App，
/// 所以原来的 App 保持前台和光标位置，关闭面板后可以直接向它粘贴。
public final class FloatingPanel: NSPanel {
    public var onClose: (() -> Void)?
    /// 返回 true 表示按键已处理，不再继续传给输入框。
    public var keyHandler: ((NSEvent) -> Bool)?

    private let panelSize: NSSize
    private var isClosing = false

    public init(size: NSSize) {
        self.panelSize = size
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    /// 输入法正在组字（比如拼音还没选词）时，回车 / 方向键应该交给输入法。
    public var isComposingText: Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    /// 面板位置：水平居中，顶边在屏幕可见区域自上而下 20% 处，且不超出可见区域。
    public static func frame(for size: NSSize, inVisibleFrame visible: NSRect) -> NSRect {
        let x = visible.midX - size.width / 2
        var y = visible.maxY - visible.height * 0.2 - size.height
        y = max(y, visible.minY)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    public func present<Content: View>(_ view: Content) {
        contentView = NSHostingView(rootView: view)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let screen {
            setFrame(Self.frame(for: panelSize, inVisibleFrame: screen.visibleFrame), display: true)
        }
        orderFrontRegardless()
        makeKey()
    }

    // 点击面板外部 → 失去 key → 关闭
    public override func resignKey() {
        super.resignKey()
        close()
    }

    public override func close() {
        guard !isClosing else { return }   // close 过程中会触发 resignKey，避免重入
        isClosing = true
        defer { isClosing = false }
        let wasVisible = isVisible
        super.close()
        if wasVisible { onClose?() }
    }

    public override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true { return true }
        // MyKit 没有主菜单，输入框里的 ⌘X / ⌘C / ⌘V / ⌘A 要自己转发
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let characters = event.charactersIgnoringModifiers {
            let action: Selector?
            switch characters {
            case "x": action = #selector(NSText.cut(_:))
            case "c": action = #selector(NSText.copy(_:))
            case "v": action = #selector(NSText.paste(_:))
            case "a": action = #selector(NSText.selectAll(_:))
            default: action = nil
            }
            if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}
```

- [ ] **Step 9: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: 全部通过。

- [ ] **Step 10: Commit**

```bash
git add Sources/Core Tests/CoreTests
git commit -m "feat: core system services - permissions watcher, paste service, event tap, floating panel"
```

---

### Task 6: 剪切板面板与模块组装

**Files:**
- Create: `Sources/ClipboardModule/ClipboardPanelViewModel.swift`, `Sources/ClipboardModule/ClipboardPanelView.swift`, `Sources/ClipboardModule/ClipboardPanelController.swift`, `Sources/ClipboardModule/ClipboardSettingsView.swift`, `Sources/ClipboardModule/ClipboardModule.swift`
- Test: `Tests/ClipboardModuleTests/ClipboardPanelViewModelTests.swift`, `Tests/ClipboardModuleTests/ClipboardModuleTests.swift`

**Interfaces:**
- Consumes:
  - `ClipboardStore`（Task 3）：`search(query:limit:offset:)`、`delete(id:)`、`clearAll()`、`purge(olderThan:)`、`openRecovering(at:)`
  - `ClipboardMonitor`、`ClipboardSettings`（Task 4）
  - `AppModule`（Task 1）；`FloatingPanel`、`PasteService`、`Permissions`（Task 5）
- Produces:
  - `@MainActor public final class ClipboardPanelViewModel: ObservableObject`：`query`、`items`、`selectedIndex`、`footerMessage`（均 `@Published`）；`init(store:pageSize:debounce:)`；`updateQuery(_:)`、`reset() async`、`reload() async`、`loadMore() async`、`moveSelection(by:)`、`select(index:)`、`selectedItem`、`item(atShortcut:)`、`deleteSelected() async`
  - `@MainActor public final class ClipboardModule: NSObject, AppModule`：`init(databaseURL: URL, defaults: UserDefaults = .standard) throws`；`static var defaultDatabaseURL: URL`；`recoveredFromCorruption: Bool`；`togglePanel()`；`isPaused: Bool`；`onPausedChange: ((Bool) -> Void)?`；`menuItems`（"打开剪切板"、"暂停记录"）；`settingsView`

按键表（来自设计文档 §3）：`↑`/`↓` 移动选中；`↩` 粘贴选中项；`⌘1`–`⌘9` 直接粘贴对应项；`⌘⌫` 删除选中项；`Esc` 关闭。输入法组字期间一律不拦截。

- [ ] **Step 1: 写失败的测试 `Tests/ClipboardModuleTests/ClipboardPanelViewModelTests.swift`**

```swift
import Foundation
import Testing
@testable import ClipboardModule

@MainActor
@Suite struct ClipboardPanelViewModelTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// 依次插入 texts，越靠后的越新。
    private func makeViewModel(_ texts: [String], pageSize: Int = 50) async throws -> (ClipboardPanelViewModel, ClipboardStore) {
        let store = try ClipboardStore(location: .inMemory)
        for (offset, text) in texts.enumerated() {
            try await store.add(text: text, appBundleID: nil, appName: nil, at: t0.addingTimeInterval(Double(offset)))
        }
        let viewModel = ClipboardPanelViewModel(store: store, pageSize: pageSize, debounce: .milliseconds(1))
        return (viewModel, store)
    }

    @Test func resetLoadsNewestFirstAndSelectsFirstRow() async throws {
        let (vm, _) = try await makeViewModel(["a", "b", "c"])

        await vm.reset()

        #expect(vm.items.map(\.text) == ["c", "b", "a"])
        #expect(vm.selectedIndex == 0)
        #expect(vm.selectedItem?.text == "c")
    }

    @Test func resetClearsQueryFooterAndSelection() async throws {
        let (vm, _) = try await makeViewModel(["apple pie", "banana"])
        vm.updateQuery("apple")
        await vm.reload()
        vm.footerMessage = "提示"

        await vm.reset()

        #expect(vm.query == "")
        #expect(vm.footerMessage == nil)
        #expect(vm.items.count == 2)
    }

    @Test func reloadFiltersByQuery() async throws {
        let (vm, _) = try await makeViewModel(["apple pie", "banana", "apple juice"])

        vm.updateQuery("apple")
        await vm.reload()

        #expect(vm.items.map(\.text) == ["apple juice", "apple pie"])
        #expect(vm.selectedIndex == 0)
    }

    @Test func updateQueryTriggersDebouncedSearch() async throws {
        let (vm, _) = try await makeViewModel(["apple pie", "banana"])
        await vm.reset()

        vm.updateQuery("banana")
        try await Task.sleep(for: .milliseconds(200))

        #expect(vm.items.map(\.text) == ["banana"])
    }

    @Test func moveSelectionClampsToBounds() async throws {
        let (vm, _) = try await makeViewModel(["a", "b", "c"])
        await vm.reset()

        vm.moveSelection(by: -1)
        #expect(vm.selectedIndex == 0)
        vm.moveSelection(by: 1)
        vm.moveSelection(by: 1)
        vm.moveSelection(by: 1)
        #expect(vm.selectedIndex == 2)
    }

    @Test func moveSelectionOnEmptyListIsNoOp() async throws {
        let (vm, _) = try await makeViewModel([])
        await vm.reset()
        vm.moveSelection(by: 1)
        #expect(vm.selectedIndex == 0)
        #expect(vm.selectedItem == nil)
    }

    @Test func selectIgnoresOutOfRangeIndex() async throws {
        let (vm, _) = try await makeViewModel(["a", "b"])
        await vm.reset()
        vm.select(index: 1)
        #expect(vm.selectedIndex == 1)
        vm.select(index: 9)
        #expect(vm.selectedIndex == 1)
    }

    @Test func shortcutNumbersMapToFirstNineRows() async throws {
        let (vm, _) = try await makeViewModel(["a", "b", "c"])
        await vm.reset()

        #expect(vm.item(atShortcut: 1)?.text == "c")
        #expect(vm.item(atShortcut: 3)?.text == "a")
        #expect(vm.item(atShortcut: 4) == nil)
        #expect(vm.item(atShortcut: 0) == nil)
        #expect(vm.item(atShortcut: 10) == nil)
    }

    @Test func deleteSelectedRemovesFromListAndStore() async throws {
        let (vm, store) = try await makeViewModel(["a", "b", "c"])
        await vm.reset()
        vm.moveSelection(by: 2)            // 选中最后一行 "a"

        await vm.deleteSelected()

        #expect(vm.items.map(\.text) == ["c", "b"])
        #expect(vm.selectedIndex == 1)     // 选中项回退到新的最后一行
        let remaining = try await store.count()
        #expect(remaining == 2)
    }

    @Test func deletingLastRemainingItemLeavesEmptyList() async throws {
        let (vm, _) = try await makeViewModel(["only"])
        await vm.reset()
        await vm.deleteSelected()
        #expect(vm.items.isEmpty)
        #expect(vm.selectedIndex == 0)
    }

    @Test func loadMoreAppendsNextPagesUntilExhausted() async throws {
        let (vm, _) = try await makeViewModel(["1", "2", "3", "4", "5"], pageSize: 2)
        await vm.reset()
        #expect(vm.items.map(\.text) == ["5", "4"])

        await vm.loadMore()
        #expect(vm.items.map(\.text) == ["5", "4", "3", "2"])

        await vm.loadMore()
        await vm.loadMore()                // 已经到底，多调用一次也不会重复
        #expect(vm.items.map(\.text) == ["5", "4", "3", "2", "1"])
    }
}
```

- [ ] **Step 2: 写失败的测试 `Tests/ClipboardModuleTests/ClipboardModuleTests.swift`**

```swift
import AppKit
import Foundation
import Testing
@testable import ClipboardModule

@MainActor
@Suite struct ClipboardModuleTests {
    private func makeModule() throws -> (ClipboardModule, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mykit-test-\(UUID().uuidString)")
        let suite = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let module = try ClipboardModule(databaseURL: dir.appendingPathComponent("clipboard.sqlite"), defaults: defaults)
        return (module, dir)
    }

    @Test func exposesIdentityAndMenuItems() throws {
        let (module, dir) = try makeModule()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(module.id == "clipboard")
        #expect(module.name == "剪切板历史")
        #expect(module.menuItems.map(\.title) == ["打开剪切板", "暂停记录"])
        #expect(module.settingsView != nil)
        #expect(!module.recoveredFromCorruption)
    }

    @Test func pausingUpdatesMenuItemStateAndNotifies() throws {
        let (module, dir) = try makeModule()
        defer { try? FileManager.default.removeItem(at: dir) }
        var notifications: [Bool] = []
        module.onPausedChange = { notifications.append($0) }

        module.isPaused = true
        #expect(module.menuItems[1].state == .on)
        module.isPaused = false
        #expect(module.menuItems[1].state == .off)
        #expect(notifications == [true, false])
    }

    @Test func defaultDatabaseLivesInApplicationSupport() {
        let path = ClipboardModule.defaultDatabaseURL.path
        #expect(path.hasSuffix("Library/Application Support/MyKit/clipboard.sqlite"))
    }
}
```

- [ ] **Step 3: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'ClipboardPanelViewModel' in scope`

- [ ] **Step 4: 写 `Sources/ClipboardModule/ClipboardPanelViewModel.swift`**

```swift
import Foundation

@MainActor
public final class ClipboardPanelViewModel: ObservableObject {
    @Published public private(set) var query = ""
    @Published public private(set) var items: [ClipboardItem] = []
    @Published public private(set) var selectedIndex = 0
    /// 面板底部的一行提示（例如未授权时的说明）
    @Published public var footerMessage: String?

    private let store: ClipboardStore
    private let pageSize: Int
    private let debounce: Duration
    private var hasMore = false
    private var isLoadingMore = false
    /// 每次重新搜索加一；异步结果回来时如果代数变了，说明结果已过时，丢弃。
    private var generation = 0
    private var searchTask: Task<Void, Never>?

    public init(store: ClipboardStore, pageSize: Int = 50, debounce: Duration = .milliseconds(80)) {
        self.store = store
        self.pageSize = pageSize
        self.debounce = debounce
    }

    public var selectedItem: ClipboardItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    /// ⌘1–⌘9 对应列表前 9 行。
    public func item(atShortcut number: Int) -> ClipboardItem? {
        guard (1...9).contains(number), items.indices.contains(number - 1) else { return nil }
        return items[number - 1]
    }

    /// 输入框文字变化时调用：防抖后重新搜索。
    public func updateQuery(_ newQuery: String) {
        guard newQuery != query else { return }
        query = newQuery
        searchTask?.cancel()
        searchTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    /// 每次打开面板时调用：清空搜索词和提示，加载最新一页。
    public func reset() async {
        searchTask?.cancel()
        query = ""
        footerMessage = nil
        await reload()
    }

    public func reload() async {
        generation += 1
        let expected = generation
        let result = (try? await store.search(query: query, limit: pageSize, offset: 0)) ?? []
        guard expected == generation else { return }
        items = result
        selectedIndex = 0
        hasMore = result.count == pageSize
    }

    public func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let expected = generation
        let more = (try? await store.search(query: query, limit: pageSize, offset: items.count)) ?? []
        guard expected == generation else { return }
        items.append(contentsOf: more)
        hasMore = more.count == pageSize
    }

    public func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), items.count - 1)
    }

    public func select(index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    public func deleteSelected() async {
        guard let item = selectedItem else { return }
        try? await store.delete(id: item.id)
        items.removeAll { $0.id == item.id }
        selectedIndex = min(selectedIndex, max(items.count - 1, 0))
    }
}
```

- [ ] **Step 5: 写 `Sources/ClipboardModule/ClipboardPanelView.swift`**

```swift
import SwiftUI

struct ClipboardPanelView: View {
    @ObservedObject var viewModel: ClipboardPanelViewModel
    let onPaste: (ClipboardItem) -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if viewModel.items.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    list.frame(width: 320)
                    Divider()
                    preview
                }
            }
            if let message = viewModel.footerMessage {
                Divider()
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .frame(width: 760, height: 460)
        .background(.regularMaterial)
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            TextField(
                "搜索剪切板历史…",
                text: Binding(get: { viewModel.query }, set: { viewModel.updateQuery($0) })
            )
            .textFieldStyle(.plain)
            .font(.system(size: 20))
            .focused($searchFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(viewModel.query.isEmpty ? "还没有复制记录" : "没有匹配的记录")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                        ClipboardRowView(
                            summary: item.summary,
                            shortcut: index < 9 ? index + 1 : nil,
                            isSelected: index == viewModel.selectedIndex
                        )
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { onPaste(item) }
                        .onTapGesture { viewModel.select(index: index) }
                        .onAppear {
                            if index == viewModel.items.count - 1 {
                                Task { await viewModel.loadMore() }
                            }
                        }
                    }
                }
                .padding(6)
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                if viewModel.items.indices.contains(newIndex) {
                    proxy.scrollTo(viewModel.items[newIndex].id)
                }
            }
        }
    }

    private var preview: some View {
        VStack(spacing: 0) {
            if let item = viewModel.selectedItem {
                ScrollView {
                    // 超长文本只预览前 2 万个字符，避免界面卡顿；粘贴时仍是完整内容
                    Text(String(item.text.prefix(20_000)))
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                Divider()
                Text(Self.caption(for: item, now: Date()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func caption(for item: ClipboardItem, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .full
        let when = formatter.localizedString(for: item.lastUsedAt, relativeTo: now)
        return "来自 \(item.appName ?? "未知应用") · \(when) · \(item.text.count) 个字符"
    }
}

private struct ClipboardRowView: View {
    let summary: String
    let shortcut: Int?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(summary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let shortcut {
                Text("⌘\(shortcut)")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }
}
```

- [ ] **Step 6: 写 `Sources/ClipboardModule/ClipboardPanelController.swift`**

```swift
import AppKit
import Core

/// 管理面板的显示 / 关闭、键盘操作和粘贴。
@MainActor
final class ClipboardPanelController {
    private let panel: FloatingPanel
    private let viewModel: ClipboardPanelViewModel
    private let isTrusted: () -> Bool

    init(viewModel: ClipboardPanelViewModel, isTrusted: @escaping () -> Bool = { Permissions.isAccessibilityTrusted }) {
        self.viewModel = viewModel
        self.isTrusted = isTrusted
        self.panel = FloatingPanel(size: NSSize(width: 760, height: 460))
        panel.keyHandler = { [weak self] event in
            self?.handleKey(event) ?? false
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if isVisible {
            panel.close()
        } else {
            show()
        }
    }

    func show() {
        Task { [weak self] in
            guard let self else { return }
            await self.viewModel.reset()   // 先加载数据再显示，避免闪一下上次的内容
            self.panel.present(ClipboardPanelView(viewModel: self.viewModel, onPaste: { [weak self] item in
                self?.paste(item)
            }))
        }
    }

    private func paste(_ item: ClipboardItem) {
        if isTrusted() {
            panel.close()
            PasteService.paste(item.text)
        } else {
            PasteService.write(item.text)
            viewModel.footerMessage = "未授予辅助功能权限，已复制，请手动按 ⌘V 粘贴"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.panel.close()
            }
        }
    }

    /// 返回 true 表示按键已处理。
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, !panel.isComposingText else { return false }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let plain = modifiers.isEmpty
        let commandOnly = modifiers == .command

        switch event.keyCode {
        case 125:   // ↓
            if plain { viewModel.moveSelection(by: 1); return true }
        case 126:   // ↑
            if plain { viewModel.moveSelection(by: -1); return true }
        case 36, 76:   // 回车、小键盘回车
            if plain {
                if let item = viewModel.selectedItem { paste(item) }
                return true
            }
        case 53:    // Esc
            panel.close()
            return true
        case 51:    // ⌫
            if commandOnly {
                Task { await viewModel.deleteSelected() }
                return true
            }
        default:
            break
        }

        if commandOnly,
           let characters = event.charactersIgnoringModifiers,
           let number = Int(characters),
           let item = viewModel.item(atShortcut: number) {
            paste(item)
            return true
        }
        return false
    }
}
```

- [ ] **Step 7: 写 `Sources/ClipboardModule/ClipboardSettingsView.swift`**

```swift
import Core
import SwiftUI

struct ClipboardSettingsView: View {
    @AppStorage private var retentionDays: Int
    let onClear: () -> Void

    @ViewState private var confirmingClear = false   // 不能写 @State，见 Global Constraints

    init(defaults: UserDefaults, onClear: @escaping () -> Void) {
        _retentionDays = AppStorage(
            wrappedValue: ClipboardSettings.defaultRetentionDays,
            ClipboardSettings.retentionDaysKey,
            store: defaults
        )
        self.onClear = onClear
    }

    var body: some View {
        Stepper(
            "历史保留 \(retentionDays) 天",
            value: $retentionDays,
            in: ClipboardSettings.retentionRange
        )
        Button("清空历史…", role: .destructive) {
            confirmingClear = true
        }
        .confirmationDialog("确定清空全部剪切板历史吗？此操作无法撤销。", isPresented: $confirmingClear) {
            Button("清空", role: .destructive, action: onClear)
            Button("取消", role: .cancel) {}
        }
    }
}
```

- [ ] **Step 8: 写 `Sources/ClipboardModule/ClipboardModule.swift`**

```swift
import AppKit
import Core
import SwiftUI

@MainActor
public final class ClipboardModule: NSObject, AppModule {
    public let id = "clipboard"
    public let name = "剪切板历史"
    /// 启动时发现数据库损坏并已重建
    public let recoveredFromCorruption: Bool
    /// 暂停状态变化时通知外壳（用于把菜单栏图标变灰）
    public var onPausedChange: ((Bool) -> Void)?

    private let store: ClipboardStore
    private let settings: ClipboardSettings
    private let defaults: UserDefaults
    private let monitor: ClipboardMonitor
    private let viewModel: ClipboardPanelViewModel
    private let panelController: ClipboardPanelController
    private var purgeTimer: Timer?

    public static var defaultDatabaseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyKit", isDirectory: true)
            .appendingPathComponent("clipboard.sqlite")
    }

    public init(databaseURL: URL, defaults: UserDefaults = .standard) throws {
        let opened = try ClipboardStore.openRecovering(at: databaseURL)
        self.store = opened.store
        self.recoveredFromCorruption = opened.recovered
        self.defaults = defaults
        self.settings = ClipboardSettings(defaults: defaults)
        self.monitor = ClipboardMonitor(pasteboard: NSPasteboard.general, store: opened.store)
        self.viewModel = ClipboardPanelViewModel(store: opened.store)
        self.panelController = ClipboardPanelController(viewModel: viewModel)
        super.init()
    }

    public func start() throws {
        monitor.start()
        purgeExpired()
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.purgeExpired()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        purgeTimer = timer
    }

    public func stop() {
        monitor.stop()
        purgeTimer?.invalidate()
        purgeTimer = nil
    }

    public func togglePanel() {
        panelController.toggle()
    }

    public var isPaused: Bool {
        get { monitor.isPaused }
        set {
            guard newValue != monitor.isPaused else { return }
            monitor.isPaused = newValue
            pauseMenuItem.state = newValue ? .on : .off
            onPausedChange?(newValue)
        }
    }

    // MARK: 菜单与设置

    private lazy var openMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "打开剪切板", action: #selector(openPanelFromMenu), keyEquivalent: "")
        item.target = self
        return item
    }()

    private lazy var pauseMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "暂停记录", action: #selector(togglePausedFromMenu), keyEquivalent: "")
        item.target = self
        return item
    }()

    public var menuItems: [NSMenuItem] {
        [openMenuItem, pauseMenuItem]
    }

    public var settingsView: AnyView? {
        AnyView(ClipboardSettingsView(defaults: defaults, onClear: { [store] in
            Task { try? await store.clearAll() }
        }))
    }

    @objc private func openPanelFromMenu() {
        panelController.show()
    }

    @objc private func togglePausedFromMenu() {
        isPaused.toggle()
    }

    private func purgeExpired() {
        let cutoff = Date().addingTimeInterval(-Double(settings.retentionDays) * 86_400)
        Task { [store] in
            _ = try? await store.purge(olderThan: cutoff)
        }
    }
}
```

- [ ] **Step 9: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: 全部通过。（`ClipboardModuleTests` 会创建 `NSPanel`；在没有图形会话的环境里可能失败，本机有图形会话，应当通过。）

- [ ] **Step 10: Commit**

```bash
git add Sources/ClipboardModule Tests/ClipboardModuleTests
git commit -m "feat: clipboard panel UI, keyboard handling and ClipboardModule assembly"
```

---

### Task 7: 总装 —— 热键接线、授权引导、偏好设置、使用说明、验收

**Files:**
- Modify: `Package.swift`（`MyKit` 依赖 `ClipboardModule`）
- Modify: `Sources/MyKit/AppDelegate.swift`（整体替换）
- Create: `Sources/MyKit/OnboardingWindowController.swift`, `Sources/MyKit/SettingsWindowController.swift`
- Create: `README.md`

**Interfaces:**
- Consumes:
  - `ModuleRegistry`、`StatusBarController`（Task 1）
  - `ModifierEventTap`、`AccessibilityWatcher`、`Permissions`（Task 5）
  - `ClipboardModule`：`init(databaseURL:)`、`defaultDatabaseURL`、`togglePanel()`、`isPaused`、`onPausedChange`、`recoveredFromCorruption`（Task 6）
- Produces: 可安装、可日常使用的 `/Applications/MyKit.app`

- [ ] **Step 1: 更新 `Package.swift`（完整内容）**

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
        .executableTarget(name: "MyKit", dependencies: ["Core", "ClipboardModule"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "ClipboardModuleTests", dependencies: ["ClipboardModule"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: 写 `Sources/MyKit/OnboardingWindowController.swift`**

```swift
import AppKit
import Core
import SwiftUI

/// 首次启动（或授权被撤销）时的引导窗口。授权完成后由 AppDelegate 调用 close()。
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let view = OnboardingView(needsPasteboardApproval: Permissions.pasteboardNeedsUserApproval)
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "欢迎使用 MyKit"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}

private struct OnboardingView: View {
    let needsPasteboardApproval: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MyKit 需要「辅助功能」权限")
                .font(.title2.bold())
            Text("有了这个权限，MyKit 才能识别你双击 Option，并把选中的内容直接粘贴到你正在用的 App 里。MyKit 不会记录你的键盘输入，也不联网。")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("1. 点击下面的「打开系统设置」")
                Text("2. 在列表里找到 MyKit，打开右边的开关")
                Text("3. 回到这里 —— 授权成功后本窗口会自动关闭")
            }
            .foregroundStyle(.secondary)

            Button("打开系统设置") {
                Permissions.openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)

            if needsPasteboardApproval {
                Divider()
                Text("还需要允许 MyKit 读取剪切板")
                    .font(.headline)
                Text("在「隐私与安全性」里找到「从其他 App 粘贴」，把 MyKit 设为「允许」。否则每次复制，系统都会弹窗询问。")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
                Button("打开隐私与安全性") {
                    Permissions.openPrivacySettings()
                }
            }

            Text("在授权之前，复制记录照常保存；你可以点右上角的 MyKit 图标 →「打开剪切板」查看。")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 460)
    }
}
```

- [ ] **Step 3: 写 `Sources/MyKit/SettingsWindowController.swift`**

```swift
import AppKit
import Core
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let modules: [AppModule]

    init(modules: [AppModule]) {
        self.modules = modules
    }

    func show() {
        if window == nil {
            let sections = modules.compactMap { module in
                module.settingsView.map { SettingsSection(id: module.id, title: module.name, view: $0) }
            }
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "MyKit 偏好设置"
            window.contentView = NSHostingView(rootView: SettingsView(sections: sections))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsSection: Identifiable {
    let id: String
    let title: String
    let view: AnyView
}

private struct SettingsView: View {
    let sections: [SettingsSection]

    var body: some View {
        Form {
            Section("通用") {
                LaunchAtLoginToggle()
            }
            ForEach(sections) { section in
                Section(section.title) {
                    section.view
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LaunchAtLoginToggle: View {
    // 不能写 @State，见 Global Constraints
    @ViewState private var enabled = SMAppService.mainApp.status == .enabled
    @ViewState private var errorText: String?

    var body: some View {
        Toggle("开机自动启动", isOn: $enabled)
            .onChange(of: enabled) { _, newValue in
                guard newValue != (SMAppService.mainApp.status == .enabled) else { return }
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    errorText = nil
                } catch {
                    errorText = "设置失败：\(error.localizedDescription)"
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
        if let errorText {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}
```

- [ ] **Step 4: 整体替换 `Sources/MyKit/AppDelegate.swift`**

```swift
import AppKit
import ClipboardModule
import Core
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.imiros.mykit", category: "app")
    private let registry = ModuleRegistry()
    private let eventTap = ModifierEventTap()
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

- [ ] **Step 5: 跑测试并构建**

Run: `scripts/test.sh && scripts/build-app.sh`
Expected: 测试全部通过；构建输出 `designated => identifier "com.imiros.mykit" and certificate leaf = H"…"` 和 `完成：build/MyKit.app`。

- [ ] **Step 6: 写 `README.md`**

````markdown
# MyKit

Mac 菜单栏小工具箱。目前的功能：**剪切板历史** —— 双击 Option 呼出，保留最近 7 天复制过的文字，可搜索，回车直接粘贴。

## 安装

在"终端"里进入本目录，依次运行：

```bash
scripts/create-dev-cert.sh   # 只需要运行一次
scripts/build-app.sh
scripts/install.sh
```

完成后屏幕右上角会出现 MyKit 图标（三层叠起来的方块）。

## 第一次使用：授权

第一次启动会弹出引导窗口：

1. 点「打开系统设置」
2. 在「辅助功能」列表里找到 MyKit，打开右边的开关
3. 引导窗口会自动关闭，授权完成

如果右上角图标变成 ⚠️ 三角形，说明授权丢失了，按上面的步骤重新打开开关即可。

## 怎么用

| 操作 | 效果 |
|---|---|
| 快速按两下 Option | 打开 / 关闭剪切板面板 |
| 直接打字 | 搜索 |
| ↑ ↓ | 选择 |
| 回车 | 粘贴到刚才正在用的 App |
| ⌘1 – ⌘9 | 直接粘贴第 1–9 条 |
| ⌘⌫ | 删除选中的记录 |
| Esc 或点击面板外 | 关闭面板 |

## 退出

**左键或右键**点击右上角的 MyKit 图标 →「退出 MyKit」。

同一个菜单里还有：打开剪切板、暂停记录、偏好设置（保留天数、开机自启、清空历史）。

## 数据在哪里

`~/Library/Application Support/MyKit/clipboard.sqlite`，只保存在本机，不联网。从密码管理器复制的密码不会被记录。

## 更新

改了代码之后重新运行 `scripts/build-app.sh && scripts/install.sh`，不需要重新授权。

## 开发

```bash
scripts/test.sh                                   # 跑全部单元测试
scripts/test.sh --filter ClipboardStoreTests      # 只跑一组
```

设计文档：`docs/superpowers/specs/2026-09-21-mykit-clipboard-design.md`
````

- [ ] **Step 7: 安装并验证剪切板隐私机制（设计文档 §5 的待验证风险）**

Run:

```bash
scripts/install.sh
sleep 3
/usr/bin/log show --last 1m --predicate 'subsystem == "com.imiros.mykit"' --info | grep "MyKit 已启动"
echo "mykit-privacy-probe-$(date +%s)" | pbcopy
sleep 2
sqlite3 "$HOME/Library/Application Support/MyKit/clipboard.sqlite" \
  "SELECT text, app_name FROM items ORDER BY last_used_at DESC LIMIT 3;"
```

Expected: 日志行里能看到 `剪切板需用户批准=false`；`sqlite3` 输出的第一行是刚才的 `mykit-privacy-probe-…`；屏幕上**没有**出现"MyKit 想要粘贴…"之类的系统弹窗。

如果实际出现了系统弹窗，或日志显示 `剪切板需用户批准=false` 但记录没有入库：把 `Sources/Core/Permissions.swift` 里的

```swift
            case .ask, .alwaysDeny:
                return true
```

改为

```swift
            case .default, .ask, .alwaysDeny:
                return true
```

重新 `scripts/build-app.sh && scripts/install.sh`，确认引导窗口出现"还需要允许 MyKit 读取剪切板"一节，并在提交信息里注明这一改动。

- [ ] **Step 8: 手动验收（需要人来操作；逐条确认，任何一条不符合就修复后重测）**

先在引导窗口里完成"辅助功能"授权。然后：

1. 在"文本编辑"里打字时双击 Option → 面板出现；菜单栏左上角的 App 名仍然是"文本编辑"（MyKit 没有抢走前台）。
2. 在面板里打字搜索（含中文输入法：拼音组字时按回车是选词而不是粘贴）、↑↓ 选择、回车 → 文本出现在"文本编辑"的光标处。
3. `⌘1`–`⌘9` 直接粘贴；`⌘⌫` 删除选中项；`Esc`、点击面板外、再次双击 Option 都能关闭面板；双击某一行也能粘贴。
4. 按 Option+字母输入特殊字符、按住 Option 拖动文件、单击一次 Option —— 都**不会**弹出面板。
5. 在"钥匙串访问"或密码管理器里复制一个密码 → 面板里**没有**这条记录。
6. 运行 `scripts/build-app.sh && scripts/install.sh` 重新安装 → 不需要重新授权，双击 Option 仍然有效。
7. 把鼠标移到第二块显示器（如果有）再双击 Option → 面板出现在鼠标所在的屏幕；在全屏 App 里也能呼出。
8. 在系统设置里关掉 MyKit 的辅助功能开关 → 几秒内右上角图标变成 ⚠️ 并弹出引导窗口；重新打开开关 → 引导窗口自动关闭，双击 Option 恢复，无需重启 MyKit。
9. **左键**点击右上角图标 → 弹出菜单；**右键**点击 → 弹出同一个菜单；菜单包含"打开剪切板 / 暂停记录 / 偏好设置… / 退出 MyKit"；点"退出 MyKit" → 图标消失，`pgrep -x MyKit` 无输出。
10. 勾选"暂停记录" → 图标变灰，此时复制的内容不入库；取消勾选后恢复记录，且暂停期间复制的内容没有被补记。
11. 偏好设置：修改保留天数后重开窗口数值仍在；"清空历史…"确认后面板为空；"开机自动启动"可以打开和关闭（系统设置 → 通用 → 登录项里能看到 MyKit）。

- [ ] **Step 9: Commit**

```bash
git add Package.swift Sources/MyKit README.md
git commit -m "feat: wire hotkey, onboarding, settings and README - MyKit clipboard history v0.1"
```



