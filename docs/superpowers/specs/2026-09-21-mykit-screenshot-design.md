# MyKit 设计文档：截图模块（第一期）

日期：2026-09-21
状态：已实现（实现计划：`docs/superpowers/plans/2026-09-21-mykit-screenshot.md`）
前置：`2026-09-21-mykit-clipboard-design.md`（外壳 + 剪切板，已实现）

## 1. 目标与范围

给 MyKit 增加一个类似 Snipaste 的截图模块，要求轻量，并比 Snipaste 多一个文字识别（OCR）。

截图模块分两期，本文档只覆盖**第一期**：

| 期 | 内容 |
|---|---|
| 第一期（本文档） | 快捷键截图、窗口边框自动识别、选区调整、复制、保存为文件、文字识别、贴图 |
| 第二期（另行设计） | 标注工具：方框、箭头、文字、马赛克、画笔、撤销 |

### 已确认的决策

| 项 | 决策 |
|---|---|
| 快捷键 | `⇧⌘A`（最初定为 ⌃⌘A，安装试用后用户改为 ⇧⌘A）；菜单栏菜单里另有"截图"一项 |
| 技术方案 | 自己做遮罩 + 定格画面：ScreenCaptureKit 截全屏 → 遮罩上框选 → 选区旁出工具条 |
| OCR 结果 | 弹出可编辑的结果窗口，同时全文自动复制到剪切板 |
| OCR 引擎 | 系统 Vision（`VNRecognizeTextRequest`），简体中文 + 繁体中文 + 英文，离线。已在本机验证可准确识别中英文混排 |
| 保存 | PNG，默认存桌面，文件夹可在设置里改 |
| 最低系统 | macOS 14（`SCScreenshotManager` 需要 14） |

### 第一期不做

标注工具（第二期）、放大镜 / 取色、长截图、录屏 / GIF、延时截图、截图历史、贴图重启后恢复、自定义快捷键。

## 2. 用户可见的行为

### 2.1 开始截图

按 `⇧⌘A`（或点菜单栏图标 →「截图」）→ 所有显示器的画面同时定格并略微变暗，鼠标变成十字。截图进行中再按一次 `⇧⌘A` = 直接退出截图（保底退出：走全局键盘监听，不依赖遮罩拿到键盘焦点）。

### 2.2 选区

```
┌──────────────────────────────────────────────────────────┐
│░░░░ 1280 × 720                                     ░░░░░░│
│░░░░┏━━━━━━━━━━■━━━━━━━━━━━┓░░░░  ░ = 变暗的部分          │
│░░░░■   选中的区域是亮的    ■░░░░  ■ = 8 个调整手柄        │
│░░░░┗━━━━━━━━━━■━━━━━━━━━━━┛░░░░                          │
│░░░░        ┌─────────────────────────────────┐░░░░░░░░░░░│
│░░░░        │ 📌贴图  🔤识别文字  💾保存  📋复制  ✕ │░░░░░░░░░░░│
│░░░░        └─────────────────────────────────┘░░░░░░░░░░░│
└──────────────────────────────────────────────────────────┘
```

- **窗口识别**：还没有选区时，鼠标下的窗口整个变亮；单击（按下到松开移动 < 3pt）即选中该窗口（裁到屏幕范围内）。鼠标下没有窗口时单击无效果。
- **自由框选**：按住拖动画出任意矩形。选区限定在拖动开始的那块显示器内。
- **调整**：选区确定后，拖 8 个手柄（命中半径 6pt）改大小，在选区内部拖动整体移动；始终不超出屏幕；最小 8×8pt；坐标取整到整数 pt。
- **尺寸标签**：选区左上角外侧显示 `宽 × 高`（单位 pt；放不下时显示在选区内侧）。
- **工具条**：选区下方右对齐；下方放不下 → 上方；上下都放不下 → 选区内右下角。拖动 / 调整期间隐藏，松手后出现。

### 2.3 操作

| 按钮 | 键盘 | 效果 |
|---|---|---|
| 复制 | `↩` / `⌘C` / 双击选区 | 图片进剪切板（PNG + TIFF），关闭遮罩，Toast「已复制」 |
| 保存 | `⌘S` | 存 PNG，关闭遮罩，Toast「已保存到 <文件夹名>」 |
| 识别文字 | `⌘R` | **遮罩不关闭**；结果面板出现在选区旁边（见 §8 第 15 条），全文自动复制 |
| 贴图 | `⌘T` | 关闭遮罩，截图原位浮在屏幕上 |
| 取消 | `Esc` / 右键 | 有选区（或正在拖）→ 清除选区回到窗口识别状态；没有选区 → 退出截图 |

还没有选区时，除取消外的按键无效果。

### 2.4 保存

- 文件名 `MyKit yyyy-MM-dd HH.mm.ss.png`；同名已存在则追加 ` (2)`、` (3)`……
- PNG 带正确的 DPI（Retina 屏截图在预览里按原始 pt 尺寸显示）。
- 保存文件夹不存在或写入失败 → 改存到桌面，Toast「保存失败，已改存到桌面」；桌面也失败 → Toast「保存失败」。
- 第一次写桌面时系统会问"是否允许 MyKit 访问桌面文件夹"，属正常。

### 2.5 文字识别结果窗口

```
┌─ 识别结果 ───────────────────────────┐
│ （可编辑、可选中部分文字的文本区）      │
├──────────────────────────────────────┤
│ ✓ 已复制全文          [重新复制] [关闭] │
└──────────────────────────────────────┘
```

- 普通窗口（会激活 MyKit，因为要打字），约 480×320，可调大小。每次识别复用同一个窗口。
- 识别期间文本区显示"正在识别…"；完成后填入文字并自动复制全文，状态行显示「✓ 已复制全文」。
- 「重新复制」复制文本区当前的全部内容（含用户的修改）。
- 没识别到文字 → 文本区为空，状态行「没有识别到文字」，不动剪切板。识别出错 → 状态行「识别失败：<原因>」。
- 行顺序：自上而下、同一行自左而右；行与行之间用换行连接。

### 2.6 贴图

- 出现在截图时的原位置、原大小；无边框、带阴影；浮在所有窗口上面，跟随所有桌面（Space），全屏 App 上也显示。
- 拖动移动；滚轮缩放（10%–500%，以窗口中心为锚点）；双击关闭。
- 右键菜单：复制 / 保存 / 识别文字 / 关闭 / 关闭全部贴图。
- 可以同时有多张；菜单栏菜单有「关闭所有贴图」。退出 MyKit 后消失。
- 贴图会被后续的截图截到（所见即所得）。

### 2.7 Toast

屏幕右上角（菜单栏下方）的小圆角提示，1.5 秒后淡出，不抢焦点、不挡鼠标。放在 `Core`，其他模块可用。

### 2.8 与剪切板模块的关系

- OCR 文字进入剪切板历史，来源显示为 MyKit：`Core.PasteService` 新增不带 own-write 标记、但带来源标记 `com.imiros.mykit.origin` 的写入方法；`ClipboardMonitor` 看到该标记时把来源记为 MyKit 自己（bundle id `com.imiros.mykit`，名称 `MyKit`）。
- 截图图片不进历史（历史只记文字）。

## 3. 权限

- 需要第二项授权**"屏幕录制"**（系统设置 → 隐私与安全性 → 录屏与系统录音）。
- 触发截图时 `CGPreflightScreenCaptureAccess()` 为 false → 调一次 `CGRequestScreenCaptureAccess()`（让 MyKit 出现在系统设置的列表里），不弹遮罩，改弹引导窗口：说明 + 「打开系统设置」（`x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`）+ 「重新启动 MyKit」。
- 该授权必须重启 App 才生效：「重新启动 MyKit」= 用 `NSWorkspace.openApplication`（`createsNewApplicationInstance = true`）拉起自身后 `terminate`。
- 没有该授权不影响剪切板功能。启动时不主动索要，只在第一次截图时引导。
- 较新的 macOS 会定期弹窗询问"是否继续允许 MyKit 录制屏幕"，系统行为，README 里说明。
- 快捷键依赖已有的"辅助功能"授权；未授权时只能从菜单栏菜单触发截图。

### 快捷键冲突（历史：最初选的 ⌃⌘A 与微信默认截图键相同）

事件监听是 `.cgSessionEventTap` + `.headInsertEventTap` + `.defaultTap`，匹配到组合键后**吞掉事件**（回调返回 nil）。现用的 `⇧⌘A` 会盖掉访达「前往应用程序」、Chrome「搜索标签页」等 App 内同键功能，且与钉钉默认截图键相同；用户已取消微信和钉钉的截图快捷键。README 里有相应说明。

## 4. 架构

新增 Target `ScreenshotModule`（依赖 `Core`），实现 `AppModule`。不改动 `ClipboardModule` 的对外行为（只给 Monitor 增加来源标记识别）。

### 4.1 Core 的改动

| 单元 | 说明 | 测试 |
|---|---|---|
| `KeyCombo` + `KeyComboMatcher` | `KeyCombo { keyCode: Int64; modifiers: CGEventFlags }`；`static let shiftCommandA`（keyCode 0）。匹配条件：`keyDown`、非自动重复、keyCode 相等、`flags ∩ {⌘,⌃,⌥,⇧}` 与 `modifiers` **完全相等** | ✅ 纯函数 |
| `ModifierEventTap` → 改名 `GlobalKeyTap` | 保留 `onDoubleTap`；新增 `register(_ combo: KeyCombo, handler: @escaping () -> Void)`。匹配到组合键时调用 handler 并吞掉事件；其余事件原样放行 | 手动 |
| `Toast` | `Toast.show(_ message: String)` | 手动 |
| `Permissions` 增补 | `isScreenRecordingGranted`、`requestScreenRecording()`、`openScreenRecordingSettings()`、`relaunch()` | 手动 |
| `PasteService` 增补 | `originMarkerType = "com.imiros.mykit.origin"`；`writeFromMyKit(_ text:to:)` 写文本 + 来源标记（不带 own-write 标记）；`write(image:pointSize:to:)` 写 PNG + TIFF | ✅ 用命名剪切板 |

### 4.2 ScreenshotModule 的单元

| 单元 | 职责 | 测试 |
|---|---|---|
| `DisplaySnapshot` | 值类型：`displayID`、`screenFrame`（AppKit 全局坐标）、`cgBounds`（CG 全局坐标，左上原点）、`scale`、`image: CGImage` | — |
| `ScreenCapturer` | `captureAll() async throws -> [DisplaySnapshot]`：`SCShareableContent` → 每块 `SCDisplay` 一个 `SCContentFilter(display:excludingWindows: [])`，`SCStreamConfiguration` 宽高 = 像素尺寸、`showsCursor = false`，`SCScreenshotManager.captureImage`；多屏并发 | 手动 |
| `WindowLocator` | `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])` → layer == 0、alpha > 0、宽高 ≥ 40、非本进程的窗口，保持前后顺序。纯函数：`localRect(cgBounds:displayBounds:)`（转成某块屏内左上原点坐标并裁到屏幕内）、`topWindow(at:in:)` | ✅ 纯函数部分 |
| `SelectionModel` | 纯状态机（屏内左上原点坐标）。状态：空闲（含悬停窗口）/ 拖出新选区 / 已选中 / 移动中 / 缩放中（8 个手柄）。输入：`mouseMoved/Down/Dragged/Up`、`cancel() -> Bool`（true = 应退出截图）。输出：`selection`、`highlight`、`isAdjusting` | ✅ |
| `ToolbarPlacement` | 纯函数：按 §2.2 规则算工具条位置 | ✅ |
| `ImageCropper` | `crop(_ image:, rect:（pt，左上原点）, scale:) -> CGImage?`：乘 scale、取整、裁到图像范围 | ✅ |
| `ScreenshotFileNamer` | 文件名与重名处理（注入"是否存在"闭包） | ✅ |
| `ScreenshotSaver` | 写 PNG（设 DPI）；失败回退桌面；返回结果枚举 | ✅ 用临时目录 |
| `ScreenshotSettings` | UserDefaults：`screenshot.saveFolder`，默认 `~/Desktop` | ✅ |
| `TextRecognizer` | Vision 包装，后台线程执行，行排序 | ✅ 用程序生成的中英文图片 |
| `CaptureOverlayController` + `OverlayView` + 工具条 | 每块屏一个无边框、不激活 App、可成为 key 的 `NSPanel`（level 高于菜单栏，`.canJoinAllSpaces`、`.fullScreenAuxiliary`）；`OverlayView`（`isFlipped = true`）画定格图、暗层、高亮 / 选区、手柄、尺寸标签；鼠标键盘事件转给 `SelectionModel`；选中后显示工具条（AppKit 按钮） | 手动 |
| `ScreenshotActions` | 复制 / 保存 / 识别 / 贴图的执行与 Toast | 手动 |
| `PinZoom` | 纯函数：滚轮增量 → 新缩放比例（夹在 0.1…5.0）→ 以中心为锚点的新 frame | ✅ |
| `PinWindow` + `PinManager` | 贴图窗口与其集合；`closeAll()` | 手动 |
| `OCRResultWindowController` | §2.5 的窗口（SwiftUI，状态放在 `ObservableObject` 里） | 手动 |
| `ScreenRecordingGuideWindowController` | §3 的引导窗口 | 手动 |
| `ScreenshotSettingsView` | 显示当前保存文件夹 +「选择…」（`NSOpenPanel`） | 手动 |
| `ScreenshotModule` | `AppModule`：`startCapture()`；菜单项「截图」（显示 ⇧⌘A）、「关闭所有贴图」；设置页 | ✅ 身份 / 菜单项 |

### 4.3 外壳接线

`AppDelegate`：注册 `ScreenshotModule`；`keyTap.register(.shiftCommandA) { screenshot.startCapture() }`。

### 4.4 坐标系约定

- CG 全局坐标：主屏左上角为原点，y 向下（`CGWindowList`、`CGDisplayBounds`）。
- AppKit 全局坐标：主屏左下角为原点，y 向上（`NSScreen.frame`、窗口 frame）。
- 遮罩内部统一用**屏内左上原点、单位 pt** 的坐标（`OverlayView.isFlipped = true`），`SelectionModel`、`WindowLocator.localRect`、`ImageCropper` 都用它；只有在创建贴图窗口时才换算回 AppKit 全局坐标。

## 5. 资源占用（"轻量"的落实）

- 遮罩窗口和定格图像只在截图期间存在，结束即释放；贴图关闭即释放其图像。
- 常驻的只有已有的那个键盘监听；不新增定时器、不新增后台线程。
- 全部系统框架（ScreenCaptureKit、Vision、AppKit），无第三方依赖。

## 6. 错误处理

| 情况 | 处理 |
|---|---|
| 无屏幕录制授权 | 不弹遮罩，弹引导窗口 |
| `captureAll` 抛错 | 记日志，Toast「截图失败」；若此时授权检查为 false 则弹引导 |
| 某块屏截取失败 | 跳过该屏，其余照常 |
| 保存失败 | §2.4 的回退 |
| OCR 失败 / 无文字 | §2.5 |
| 截图进行中再次触发 | 遮罩已显示 → 结束本次截图（保底退出）；还在定格画面 → 忽略 |

## 7. 测试

自动化（Swift Testing）：`KeyComboMatcher`、`PasteService` 新方法、`ClipboardMonitor` 来源标记、`WindowLocator` 纯函数、`SelectionModel`（悬停、单击选窗、拖出选区、移动、8 个手柄缩放、边界夹取、最小尺寸、两级取消）、`ToolbarPlacement`、`ImageCropper`（含 2× 缩放与越界）、`ScreenshotFileNamer`、`ScreenshotSaver`（含回退）、`ScreenshotSettings`、`TextRecognizer`（生成中英文图片做真实识别；空白图片返回空）、`PinZoom`、`ScreenshotModule` 身份与菜单项。

手动验收清单（实现计划的最后一个任务里逐条列出）：授权引导与重启、`⇧⌘A` 触发与吞键、微信冲突实测、窗口高亮与单击选窗、框选 / 移动 / 缩放、工具条位置、五个操作及其快捷键、两级取消、多显示器、Retina 清晰度、贴图的拖动 / 缩放 / 右键菜单 / 多张 / 全屏 App 上显示、OCR 结果窗口的编辑与重新复制、OCR 文字在剪切板历史里来源显示为 MyKit、保存文件夹设置与回退、截图结束后内存回落。

## 8. 实现阶段的细化（写计划并编译验证时确定）

1. §4.1：`KeyComboMatcher.matches` 不含"是否自动重复"参数；`GlobalKeyTap` 对自动重复的按键同样吞掉，但只在第一次按下时调用 handler。
2. §4.1：`Core` 新增 `ImageEncoding`（带 DPI 的 PNG / TIFF 编码），`PasteService.write(image:)` 与 `ScreenshotSaver` 共用。
3. §4.2：`DisplaySnapshot` 实际为 `{ screen: ScreenDescriptor, image }`，带 `localBounds` 与 `imageScale`；裁剪与换算回 AppKit 全局坐标放在新增的 `CaptureResult.make`。
4. §4.2：新增小单元 `CaptureAction`、`OverlayCommand`、`OverlayKeyMap`（已测）、`CaptureToolbar`、`OCRResultModel`（已测，识别与复制均为注入）、`ScreenshotActions.message(for:)`。
5. §2.2：已有选区时，在选区外**拖动**会开始画新选区；在选区外**单击**则保留原选区。`SelectionModel` 增加 `hasConfirmedSelection` 与 `reset()`。
6. §2.5：同一视觉行上的多个识别片段用空格连接，行与行之间用换行连接。
7. 鼠标离开某块屏时清除该屏上的窗口高亮；同一时间只有一块屏上有选区。
8. 从菜单栏菜单触发截图时延迟 0.25 秒，避免把菜单本身截进去。
9. 截图期间遮罩面板吞掉所有键盘事件（不会传给下面的 App，也不会发出系统提示音）。
10. 保底退出：遮罩显示期间再按 `⇧⌘A` 直接结束截图（走全局键盘监听，不依赖遮罩的键盘焦点）。
11. 用户已取消微信和钉钉的截图快捷键，§3 的冲突实测不再需要；README 保留一句提示，供日后分享给他人时参考。
12. 环境发现：Swift Testing 的 `#expect` 里不能直接写字面量算术（如 `x == 1600 - 16`），需先用 `let` 算好；Vision 在新进程身份下首次识别约 20–25 秒，之后约 0.3 秒。
13. 快捷键变更：用户试用后要求把截图快捷键从 ⌃⌘A 改为 ⇧⌘A（`KeyCombo.shiftCommandA`）。实现计划文档保留原始的 ⌃⌘A 写法，以本条为准。
14. 快捷键可自定义（用户试用后提出"应该增加快捷键功能，这样就能随时更改"）：
    - `Core` 新增 `HotkeySettings`（UserDefaults：`hotkey.screenshot.keyCode / modifiers / keyLabel`、`hotkey.clipboard.doubleTap`；修改时发 `didChangeNotification`，object = 对应的 UserDefaults）、`DoubleTapModifier`（option / control / command，不提供 Shift —— 中文输入法用它切换中英文）、`KeyLabel`、`HotkeyValidator`（普通键必须带 ⌘/⌃/⌥ 之一，F1–F12 可单独用，⌘ + A/C/V/X/Z/Q/W/H/M/Tab/Space 保留）、`HotkeyRecorderModel` + `HotkeyRecorderView`。
    - `ModifierEventTranslator.translate` 增加 `target:` 参数；`GlobalKeyTap` 增加 `doubleTapModifier`、`unregisterAll()`、`isSuspended`。
    - `AppDelegate.applyHotkeys()` 按设置重新注册，监听变更通知，改完立即生效；录制新快捷键期间（`recordingDidBegin/End` 通知）暂停全局监听，否则现有快捷键会被吞掉、录不进去；录制 15 秒无输入自动取消，避免全局快捷键被一直暂停。
    - 截图设置页的"快捷键"一行改为录制控件 +「恢复默认」；剪切板设置页新增「呼出方式」；菜单里「截图」显示的快捷键随设置更新（功能键无法用单字符表示时不显示）。
    - 这一条同时取代了两份设计文档"第一期不做"清单里的"自定义快捷键 / 自定义热键"。
15. 识别文字时遮罩不关闭（用户试用后提出"识别文字的时候，截图页面不要关闭"，为了对照原图检查识别结果）：
    - 从遮罩发起的识别不再走 `onFinish`：`CaptureOverlayController` 自己持有一个 `OCRResultModel`，用 `Core.FloatingPanel`（不激活 App、可输入、level = 遮罩层级 + 1，380×300）把 `OCRResultView` 显示在选区旁边。位置由纯函数 `ToolbarPlacement.sidePanelOrigin` 决定：右 → 左 → 下 → 上 → 选区内右下角，始终完整落在屏幕内（已测）。
    - 面板按钮为「重新复制」「完成」。「完成」或 `Esc`（输入法组字时除外）= 结束整个截图。
    - 点一下定格画面（或工具条）→ 面板失去焦点自动收起，回到截图状态：可以调整选区再次识别，或继续复制 / 保存 / 贴图。
    - 从贴图右键菜单发起的识别没有遮罩，仍用 §2.5 的普通窗口；两处共用 `OCRResultView`（关闭按钮的文字可配置）。
    - `FloatingPanel.present` 增加可选参数 `at frame:`，用于指定位置。
16. 识别结果可翻译成中文（用户提出"识别的时候增加一个翻译，增加个选项，翻译成中文，识别英文就行"）：
    - 引擎：系统 `Translation` 框架（macOS 15+，离线、免费、无第三方依赖），固定 英文 → 简体中文。已在本机验证：CLT 下可编译；该语言对状态为 supported（语言包未下载）。macOS 14 上不显示该选项（`#available`）。
    - 界面：`OCRResultView` 增加「翻译成中文」勾选框；勾上后下半部分显示译文（可选中 / 编辑），按钮变为「复制译文」「复制原文」。勾选状态存 `screenshot.autoTranslate`，勾上后每次识别完自动翻译。译文不自动进剪切板（原文仍自动复制）。
    - 状态在 `OCRResultModel`（已测）：`translateEnabled`、`translation`、`translationStatus`、`isTranslating`、`translationRequestID`；`setTranslateEnabled`、`requestTranslation`、`runTranslation(_:)`（翻译函数注入）、`copyTranslation`、`adopt(text:)`、`cancelPendingTranslation`。没有英文（`TranslationText.containsEnglish`：连续 ≥ 2 个英文字母）→ 提示"没有可翻译的英文"，不发请求。
    - 段落合并（`TranslationText.paragraphs`，已测）：截图里的段落被换行切碎，逐行翻译质量差。上一行未以句末标点结尾、且长度 ≥ max(最长行 × 0.6, 25 字符) 时与下一行用空格合并；空行分段；菜单项 / 标题等短行不合并。每段一个 `TranslationSession.Request`，译文按段用换行连接。
    - 执行：视图修饰器 `TranslationRunner` 用 `.translationTask` 取得会话，先 `prepareTranslation()`（需要时系统提示下载语言包）再 `translations(from:)`。
    - 语言包未安装且处在截图遮罩上时：系统的下载提示可能被全屏遮罩挡住，所以先用 `LanguageAvailability` 检查，未安装则结束截图，经 `onContinueInWindow` 把已识别的文字交给普通的识别结果窗口（`OCRResultWindowController.continueWith(text:)`）在那里下载并翻译。
    - 面板尺寸改为 400×440，普通窗口改为 480×460，给译文留出空间。
    - 未能自动验证（需要真机操作）：语言包下载提示的实际表现、`.translationTask` 在不激活 App 的面板里的表现、译文质量。
17. 翻译时也不关闭截图（用户试用后提出"翻译的时候也不要关闭截图"；第 16 条里"语言包未安装时结束截图、换到普通窗口"的做法作废，相关代码已删除）：
    - 语言包未安装时仍在遮罩上原地执行 `prepareTranslation()`。为了不挡住系统的下载提示，`OCRResultView.onLanguageDownloadActive(true)` 通知 `CaptureOverlayController.yieldToSystemPrompt`：遮罩面板与结果面板临时降到 `.normal` 层级（画面仍在，菜单栏会露出来）；本次翻译结束、结果面板收起或截图结束时恢复为遮罩层级。
    - `FloatingPanel` 新增 `closesOnResignKey`（默认 true）。遮罩上的结果面板设为 false：系统提示框抢走键盘焦点时面板不能关闭（否则翻译任务会被取消）；面板只在点击定格画面 / 工具条时收起（`overlayViewDidBeginInteraction`）。
    - 翻译失败且语言包仍未安装时，`OCRResultModel.reportLanguagePackMissing()` 把提示换成具体办法：在系统提示里点「下载」，或手动到 系统设置 → 通用 → 语言与地区 → 翻译语言 下载「英语」和「简体中文」（已测）。
    - 仍需真机确认：下载提示在降级后的遮罩上是否可见、下载完成后是否需要重新勾选一次。
18. 贴图支持触控板双指捏合缩放（用户试用后提出）：`PinZoom.scale(current:magnification:)`（相对当前大小、夹在 10%…500%、异常负值不会让图片翻转，已测），`PinWindow` 的内容视图响应 `magnify(with:)`；原有的滚轮 / 双指滑动缩放保留。
