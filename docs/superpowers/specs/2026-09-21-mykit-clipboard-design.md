# MyKit 设计文档：应用外壳 + 剪切板历史模块

日期：2026-09-21
状态：设计已确认，待写实现计划

## 1. 目标与范围

MyKit 是一个 macOS 菜单栏常驻工具，定位是"集成很多小功能的个人工具箱"。本文档覆盖第一个子项目：

- 可扩展的应用外壳（模块协议、全局热键、浮动面板、粘贴服务、权限引导）
- 第一个模块：剪切板历史（类似 Alfred 5 的 Clipboard History）

后续模块（文本片段、截图 / OCR / 翻译）各自单独走"设计 → 计划 → 实现"流程，不在本文档范围内；本设计只保证它们能以新模块的形式接入而不改动剪切板代码。

### 核心用户故事

双击 Option → 屏幕上出现面板，列出最近 7 天复制过的文本 → 直接打字搜索 → 回车 → 面板消失，选中的文本被粘贴到刚才正在输入的位置。

### 已确认的决策

| 项 | 决策 |
|---|---|
| 记录内容 | 仅文本 |
| 保留期 | 默认 7 天，可在设置中修改 |
| 回车行为 | 直接粘贴到当前 App |
| 分发 | 先自用，以后可能分享给朋友（不上架 App Store，不做沙盒） |
| 技术栈 | 原生 Swift：AppKit + SwiftUI，SwiftPM 构建 |
| 软件名 | MyKit，bundle id `com.imiros.mykit` |

### 环境约束

- macOS 27，Swift 6.4，仅安装 Command Line Tools，**没有完整 Xcode**。
- 因此：用 SwiftPM 构建、脚本组装 `.app`；测试框架用 Swift Testing（CLT 自带），不用 XCTest（CLT 不带）。
- macOS 27 SDK 把 SwiftUI 的 `@State` 改成了宏，宏插件只随 Xcode 提供；代码里统一用别名 `@ViewState`（指向底层属性包装器 `SwiftUI.State`）绕开。
- 本机当前没有任何代码签名证书。

## 2. 架构

### 软件形态

菜单栏 agent 应用（Info.plist 设 `LSUIElement = true`，无 Dock 图标）。屏幕右上角菜单栏常驻一个 MyKit 图标，**左键或右键点击都弹出同一个菜单**：

| 菜单项 | 说明 |
|---|---|
| 打开剪切板 | 等同于双击 Option（由剪切板模块通过 `AppModule.menuItems` 提供） |
| 暂停记录 | 勾选状态，暂停时图标变灰（同样由剪切板模块提供） |
| 偏好设置… | 打开设置窗口 |
| 退出 MyKit | 菜单最后一项，快捷键 ⌘Q，点击后立即退出（停止所有模块、关闭数据库） |

实现上给 `NSStatusItem` 直接设置 `menu` 属性即可，系统默认对左右键都弹出该菜单，不需要单独处理右键事件。

### 工程结构

一个 SwiftPM 包，三个 Target 加对应测试 Target：

| Target | 类型 | 职责 | 依赖 |
|---|---|---|---|
| `Core` | 库 | 模块协议、双击修饰键检测、浮动面板基础设施、粘贴服务、权限检查 | 系统框架 |
| `ClipboardModule` | 库 | 剪切板监听、存储、搜索、面板界面 | `Core` |
| `MyKit` | 可执行 | 启动、菜单栏、模块注册、偏好设置窗口、权限引导窗口 | `Core`、`ClipboardModule` |
| `CoreTests` / `ClipboardModuleTests` | 测试 | Swift Testing | 对应库 |

不引入第三方依赖；SQLite 用系统自带的 `SQLite3`。

### 模块协议

```swift
@MainActor
public protocol AppModule: AnyObject {
    var id: String { get }
    var name: String { get }
    func start() throws
    func stop()
    var menuItems: [NSMenuItem] { get }      // 可为空
    var settingsView: AnyView? { get }       // 可为 nil
}
```

外壳持有 `[AppModule]`，启动时逐个 `start()`，把各模块的菜单项拼进菜单栏菜单、设置页拼进偏好设置窗口。新增功能 = 新增 Target + 在 `MyKit` 里注册一行。

### Core 内的单元

| 单元 | 作用 | 对外接口 |
|---|---|---|
| `DoubleTapDetector` | 纯状态机，判定"双击某修饰键" | `handle(event:at:) -> Bool`，不依赖系统 API |
| `ModifierEventTap` | 包装 `CGEventTap`，把 `flagsChanged` / `keyDown` 转成状态机事件，触发时回调 | `start()`、`stop()`、`onDoubleTap` |
| `FloatingPanel` | `NSPanel` 子类，non-activating、浮动层级、可成为 key window | `show(content:)`、`close()`、`onClose` |
| `PasteService` | 写剪切板 + 发送 ⌘V | `paste(text:)` |
| `Permissions` | 辅助功能授权的检测与跳转 | `isTrusted`、`openSettings()`、授权状态变化回调 |

## 3. 剪切板模块

### 数据流

```
NSPasteboard ──每 0.5s 查 changeCount──▶ ClipboardMonitor ──过滤──▶ ClipboardStore (SQLite)
                                                                        ▲
                                                 面板 UI ──查询 / 删除──┘
```

### ClipboardMonitor

- macOS 没有剪切板变更通知，用 0.5s 定时器轮询 `NSPasteboard.general.changeCount`；变化时读取 `.string`。
- 过滤规则（做成纯函数，便于测试）：
  - 剪切板类型中含 `org.nspasteboard.ConcealedType` 或 `org.nspasteboard.TransientType` → 跳过（密码管理器）。
  - 含 MyKit 自己的标记类型 `com.imiros.mykit.own-write` → 不新增，只把对应记录移到最前。
  - 去除首尾空白后为空 → 跳过。
  - UTF-8 长度超过 1MB → 跳过。
- 来源 App 取变化发生时的 `NSWorkspace.shared.frontmostApplication`（bundle id + 本地化名称）。
- "暂停记录"开启时定时器照常运行但只同步 changeCount，不读取内容。

### ClipboardStore

位置：`~/Library/Application Support/MyKit/clipboard.sqlite`。

```sql
CREATE TABLE items (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  text        TEXT    NOT NULL,
  text_hash   TEXT    NOT NULL UNIQUE,   -- SHA-256，用于去重
  app_bundle  TEXT,
  app_name    TEXT,
  created_at  REAL    NOT NULL,          -- 首次复制时间
  last_used_at REAL   NOT NULL           -- 最近一次复制/粘贴时间，排序依据
);
CREATE INDEX idx_items_last_used ON items(last_used_at DESC);
CREATE VIRTUAL TABLE items_fts USING fts5(text, content='items', content_rowid='id', tokenize='trigram');
-- 配套 INSERT / DELETE / UPDATE 触发器保持 items_fts 同步
```

接口：

- `add(text:app:at:)`：哈希已存在则只更新 `last_used_at`（移到最前），否则插入。
- `search(query:limit:offset:)`：query 为空 → 按 `last_used_at` 倒序；长度 ≥ 3 → FTS5 trigram 匹配；长度 1–2 → `LIKE '%q%'`（trigram 不支持短于 3 的查询）。结果一律按 `last_used_at` 倒序。
- `delete(id:)`、`clearAll()`、`purge(olderThan:)`。
- 过期清理：按 `last_used_at` 判断；启动时执行一次，之后每小时一次。
- 所有数据库访问走一个串行队列，UI 通过 async 接口调用。

### 面板 UI

```
┌────────────────────────────────────────────────────────┐
│ 🔍 搜索剪切板历史…                                      │
├───────────────────────────┬────────────────────────────┤
│ ▸ git rebase -i HEAD~3  ⌘1│ git rebase -i HEAD~3       │
│   https://github.com/…  ⌘2│                            │
│   张三 13800000000      ⌘3│ （完整文本预览，可滚动）     │
│   SELECT * FROM user…   ⌘4│────────────────────────────│
│   …                       │ 来自 iTerm · 今天 14:32     │
│                           │ 42 个字符                   │
└───────────────────────────┴────────────────────────────┘
```

- 左侧列表每行：**来源 App 的图标**（一眼看出从哪里复制的，鼠标悬停显示"来自 XX"）+ 文本的单行摘要（压缩空白、截断），前 9 行显示 ⌘1–⌘9 提示。
- 右侧预览显示完整文本；底部是来源栏：来源 App 的大图标 + "来自 XX"（醒目）+ 相对时间、字符数（次要）。
- 图标由 `AppIconProvider` 按 bundle id 查找并缓存；来源未知或来源 App 已卸载时显示通用占位图标，名称显示"未知应用"。
- 来源 = 复制发生时的前台 App。同一段文本再次从别的 App 复制时，来源更新为最近一次的 App。
- 打开时清空搜索词、选中第一条；直接打字即搜索（80ms 防抖）；首屏 50 条，滚动到底继续加载。
- 面板出现在鼠标所在屏幕的中央偏上，固定尺寸约 760×460。

| 按键 | 行为 |
|---|---|
| `↑` `↓` | 移动选中项 |
| `↩` | 粘贴选中项 |
| `⌘1`–`⌘9` | 直接粘贴对应项 |
| `⌘⌫` | 删除选中项 |
| `Esc` / 点击面板外 / 再次双击 Option | 关闭面板 |

## 4. 全局热键与自动粘贴

### 双击 Option 判定（DoubleTapDetector）

输入事件：`modifierDown(key, otherModifiersHeld)`、`modifierUp(key)`、`otherKeyDown`，均带时间戳。

- 一次"有效轻按" = Option 单独按下（无其他修饰键）→ 松开，期间没有任何其他按键，且按住时长 ≤ 300ms。
- 两次有效轻按的间隔（第一次松开到第二次按下）≤ 300ms → 触发。
- 任何其他按键、其他修饰键、超时 → 重置。因此 Option+字母输入特殊字符不会误触发。
- 左右 Option 都算。
- 触发时面板已打开 → 关闭面板（toggle）。

### 面板不抢焦点

`FloatingPanel` 使用 `.nonactivatingPanel` style mask、`.floating` level、`canBecomeKey = true`、`hidesOnDeactivate = false`。面板能接收键盘输入，但 MyKit 不会成为 active app，原 App 保持前台和光标位置。面板失去 key 状态时自动关闭。

### 粘贴流程（PasteService）

1. 清空系统剪切板，写入选中文本，同时写入标记类型 `com.imiros.mykit.own-write`。
2. 关闭面板。
3. 延迟 50ms 后，用 `CGEvent` 向 HID 事件流发送 `⌘V` 的按下与抬起。
4. Monitor 在下一次轮询中识别到自己的标记，只把该记录移到最前。

## 5. 权限

- 只需要"辅助功能"一项授权（事件监听和模拟按键都依赖它）。
- 启动时 `AXIsProcessTrusted()` 为 false → 显示引导窗口：说明用途 + "打开系统设置"按钮；每秒轮询，授权后自动启动 event tap 并关闭窗口，无需重启。
- 未授权期间剪切板记录照常工作，菜单栏"打开剪切板"可用（但回车只复制不粘贴，并提示原因）。
- 运行中授权被撤销（event tap 创建失败或被禁用且无法恢复）→ 菜单栏图标切换为警告样式，重新弹出引导窗口。
- event tap 收到 `tapDisabledByTimeout` / `tapDisabledByUserInput` → 自动重新启用。

### 待验证风险：剪切板隐私提示

macOS 15.4 起系统引入了"App 在无用户操作时读取剪切板"的隐私机制（`NSPasteboard.accessBehavior`），较新系统上可能对后台读取弹出提示，需要用户在"隐私与安全性 → 从其他 App 粘贴"中将 MyKit 设为"始终允许"。引导窗口根据 `accessBehavior`（`.ask` / `.alwaysDeny`）决定是否显示"还需要允许 MyKit 读取剪切板"一节。签名后的 `.app` 第一次真实运行监听时（实现计划 Task 7 Step 7）在 macOS 27 上验证实际行为；如果 `.default` 下也会弹系统提示，则把 `.default` 一并视为需要用户批准。

## 6. 设置

偏好设置窗口（SwiftUI `Form`），第一版只包含：

- 保留天数（默认 7，范围 1–90）
- 开机自启（`SMAppService.mainApp`）
- 清空历史（带确认）

配置存 `UserDefaults`。"暂停记录"放在菜单栏菜单里，不进设置窗口。

## 7. 构建与签名

- `scripts/build-app.sh`：`swift build -c release --build-system native` → 组装 `build/MyKit.app`（`Contents/MacOS/MyKit`、`Info.plist`、`Resources/AppIcon.icns`）→ `codesign`。
- `scripts/test.sh`：包装 `swift test`。已在本机验证：仅有 Command Line Tools 时，默认的 swiftbuild 构建系统无法初始化，必须用 `--build-system native`；且需要显式传入 Swift Testing 的框架路径、宏插件路径和 rpath，测试才能编译运行。
- `scripts/create-dev-cert.sh`：一次性用 `openssl` 生成自签名代码签名证书 `MyKit Dev`，导入**专用钥匙串** `~/Library/Keychains/mykit-dev.keychain-db`（固定密码，不加入钥匙串搜索列表）。构建时用 `codesign --keychain` 指定它。已在本机验证：全程无需用户输入登录密码，签名后的 designated requirement 为 `identifier "com.imiros.mykit" and certificate leaf = H"…"`，重新编译后保持不变。
- 必须使用固定证书签名：辅助功能授权绑定代码签名身份，ad-hoc 签名每次重新编译都会导致授权失效。证书不存在时构建脚本报错并提示先运行 `create-dev-cert.sh`。
- `scripts/install.sh`：退出正在运行的 MyKit → 复制到 `/Applications/MyKit.app` → 重新打开。
- 日后分享给他人：把签名身份换成 Apple Developer ID 并加 `notarytool` 公证步骤，工程结构不变。

## 8. 错误处理

| 情况 | 处理 |
|---|---|
| 数据库打不开 / 损坏 | 旧文件改名为 `clipboard.sqlite.corrupt-<时间戳>`，新建数据库，菜单栏提示一次 |
| event tap 被系统禁用 | 自动重新启用；失败则按"授权被撤销"处理 |
| 未授权时按回车 | 只复制到剪切板，面板底部提示"未授予辅助功能权限，已复制，请手动 ⌘V" |
| 单次写库失败 | 记日志（`os.Logger`），丢弃该条，不打断监听 |

## 9. 测试

自动化（Swift Testing）：

- `DoubleTapDetector`：正常双击触发；间隔超时不触发；按住过久不触发；中间夹其他键不触发；带其他修饰键不触发；左右 Option 混合触发；触发后状态复位。
- `ClipboardStore`（内存数据库）：插入；重复文本去重并移到最前；`purge` 只删过期项；FTS 搜索；1–2 字符退回 LIKE；中文子串搜索；含 FTS 特殊字符（引号、`*`）的查询不报错；分页；删除后 FTS 同步。
- Monitor 过滤函数：Concealed / Transient 跳过；自己写入识别；空白跳过；超长跳过。

手动验收清单（依赖真实系统环境，无法自动化）：

1. 在 TextEdit 中输入时双击 Option，面板出现且 TextEdit 仍是前台 App。
2. 打字搜索、↑↓ 选择、回车后文本粘贴到 TextEdit 光标处。
3. ⌘1–9、⌘⌫、Esc、点击面板外、再次双击 Option 行为正确。
4. Option+字母输入特殊字符、按住 Option 拖拽等操作不误触发。
5. 从 1Password / 钥匙串复制的密码不出现在历史中。
6. 重新编译并签名后，辅助功能授权仍然有效。
7. 全屏 App、多显示器下面板出现在鼠标所在屏幕。
8. 首次启动引导：未授权 → 授权后无需重启即可双击 Option。
9. 右键（以及左键）点击右上角菜单栏图标，弹出菜单；点"退出 MyKit"后图标消失、进程结束。

## 10. 第一版不做

图片 / 文件记录、忽略指定 App 名单、记录置顶 / 收藏、iCloud 同步、合并粘贴、富文本格式保留。

（原先列在这里的"自定义热键"已在截图模块阶段实现：呼出方式可选 双击 Option / Control / Command，见截图设计文档 §8 第 14 条。）

## 11. 后续模块路线图

每个模块单独走"设计 → 计划 → 实现"，以新 Target 实现 `AppModule` 后注册进外壳。

| 顺序 | 模块 | 用户已提出的要求 | 已知的技术要点 |
|---|---|---|---|
| 2 | 截图 + 文字识别 | 类似 Snipaste 的截图体验；要轻量；比 Snipaste 多一个文字识别（OCR） | 截图用系统 ScreenCaptureKit，OCR 用系统 Vision（支持中英文，离线，无第三方依赖）；需要第二项授权"屏幕录制"；需要一个普通组合键热键 → 届时在 `Core` 增加通用热键注册 |
| 3 | 文本片段 / 快捷短语 | 待定 | 复用 `FloatingPanel` 与 `PasteService` |
| — | 翻译 | 待定 | 可接在 OCR 结果之后 |

截图模块的具体范围（是否要贴图钉在屏幕上、标注工具、取色等）在其自己的设计环节确定。
