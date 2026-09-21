# MyKit 设计文档：卸载器模块

日期：2026-09-21
状态：设计已确认，待写实现计划
前置：外壳、剪切板、截图（含标注）、系统监控均已实现

## 1. 目标与范围

在 MyKit 里增加"卸载软件"：选中一个已安装的软件，找出它本体和散落在各处的残留文件（**包括隐藏文件**），让用户确认后移到废纸篓。用户要求"卸载得彻底"。

### 已确认的决策

| 项 | 决策 |
|---|---|
| 选择方式 | 窗口左侧是已安装软件列表（可搜索、可按名称 / 大小排序），也可以把 `.app` 从访达拖进窗口 |
| 删除方式 | **只移到废纸篓**，绝不永久删除；执行前列出清单并确认 |
| 彻底程度 | 扫描范围尽量全：`~/Library` 的各个位置、主目录下的隐藏文件、每用户缓存 / 临时目录、系统级 `/Library` 与安装记录 |
| 误删防护 | 分两类：**确定相关**（名称含该软件独有的标识符，默认勾选）与**可能相关**（同名 / 名称沾边，默认不勾选）；有「全选」按钮 |
| 系统软件 | 不可卸载、不出现在列表里 |
| 需要管理员权限的项 | 交给访达执行（系统自己弹密码框），MyKit 不接触密码 |

### 不做

自动发现"用户刚把某软件拖进废纸篓"并提示清理（需要常驻监视）、清空废纸篓、浏览器插件 / 系统扩展 / 内核扩展的专门卸载流程、批量卸载多个软件、卸载历史、卸载 Homebrew / 命令行工具。

## 2. 用户可见的行为

### 2.1 入口与窗口

菜单栏菜单新增「卸载软件…」→ 打开卸载窗口（普通窗口，约 860×560，可调大小，会激活 MyKit）。窗口关闭后释放全部数据。

```
┌─ 卸载软件 ─────────────────────────────────────────────────────────────┐
│ 🔍 搜索软件…     [名称|大小] │  💬 微信  3.8.2                共 9 项，2.31 GB │
├──────────────────────────────┤  [全选] [只选确定相关]                        │
│ 💬 微信               1.2 GB │ ─────────────────────────────────────────── │
│ 🌐 Google Chrome      980 MB │ 确定相关                                     │
│ 📎 钉钉               760 MB │  ☑ 📦 微信.app          /Applications  1.2 GB│
│ …                            │  ☑ 📁 容器数据          ~/Library/Con… 980 MB│
│                              │  ☑ 📄 偏好设置          ~/Library/Pre…   4 KB│
│                              │ 可能相关（默认不勾选，请自己判断）            │
│                              │  ☐ 📁 .wechat           ~/             35 MB │
│                              │ 需要管理员密码                               │
│                              │  ☑ 📄 后台服务          /Library/Launc…  2 KB│
│  把 .app 拖到窗口里也可以     │              [在访达中显示]   [移到废纸篓]    │
└──────────────────────────────┴─────────────────────────────────────────────┘
```

### 2.2 软件列表

- 来源：`/Applications`、`/Applications/Utilities`、`~/Applications`，以及它们的一级子文件夹里的 `.app`（不递归进 `.app` 内部）。
- 每行：图标、显示名、大小。大小在后台逐个计算（低优先级），算好一个显示一个；窗口生命周期内缓存。未算好时显示"计算中…"。
- 搜索：按显示名和 bundle id 做不区分大小写的包含匹配。
- 排序：名称（本地化比较）/ 大小（大的在前，未算好的排最后）。
- 受保护的软件（§4）不出现在列表里。
- 拖入：接受单个 `.app`（任意位置，例如"下载"文件夹里的）。受保护 → 提示"这是系统软件，不能卸载"；不是 `.app` → 忽略。

### 2.3 清单

选中软件后在后台扫描，期间显示"正在查找相关文件…"。清单分三组，每组内按大小从大到小：

| 组 | 默认 | 含义 |
|---|---|---|
| 确定相关 | 勾选 | 软件本体；名称含该软件 bundle id 的项；在 Application Support / Caches / Logs 等目录下与软件名**完全相同**的文件夹 |
| 可能相关 | 不勾选 | 名称只是"沾边"的项（见 §3.3），包括主目录下同名的隐藏文件 / 文件夹 |
| 需要管理员密码 | 勾选（仅当它同时属于"确定相关"）；否则不勾选 | 位于系统级目录、当前用户无权移动的项 |

- 每行：勾选框、类型图标、中文类别名（§3.2）、缩短的路径（悬停显示完整路径）、大小。
- 「全选」勾上所有项；「只选确定相关」恢复默认勾选。标题行实时显示已勾选的项数和总大小。
- 「在访达中显示」对当前高亮的行生效。
- 软件本体那一行和其他行一样可以取消勾选：用户可以只清残留、不删本体，也可以反过来。

### 2.4 执行

1. 点「移到废纸篓」→ 若目标软件正在运行：提示"XX 正在运行"，按钮「退出 XX 并继续」（`NSRunningApplication.terminate()`，最多等 5 秒；仍未退出则提示用户手动退出，不强制结束）。
2. 确认框："将把 N 项（X GB）移到废纸篓。可以从废纸篓恢复。"
3. 逐项执行（§5）。窗口显示进度。
4. 结果："已移到废纸篓 N 项，释放 X GB"；失败的项逐条列出原因。若移走了后台服务 / 特权帮助程序，附加一句"其中的后台服务在重启电脑后才会完全停止"。
5. 完成后从列表里移除该软件（本体已移走时），清单清空。

## 3. 扫描规则

### 3.1 软件的标识

从 `.app` 的 `Info.plist` 取：`CFBundleIdentifier`（bundle id）、`CFBundleName` / `CFBundleDisplayName`、文件名（去掉 `.app`）。没有 bundle id 的软件只能做名称匹配。

派生出用于匹配的"名称变体"：显示名、`CFBundleName`、文件名，以及它们各自去掉空格的形式；全部做不区分大小写的比较。长度 < 3 的变体丢弃。

厂商片段：bundle id 的第二段（`com.tencent.xinWeChat` → `tencent`），长度 ≥ 4 且不在通用词黑名单里（`apple`、`google`、`microsoft`、`github`、`app`、`mac`、`macos`、`company`、`software`、`desktop`、`client`）时才使用，只用于"可能相关"。

### 3.2 扫描位置

用户级（当前用户可直接移动）：

| 位置 | 类别名 |
|---|---|
| `~/Library/Application Support` | 应用数据 |
| `~/Library/Caches` | 缓存 |
| `~/Library/Preferences`、`~/Library/Preferences/ByHost` | 偏好设置 |
| `~/Library/Logs`、`~/Library/Logs/DiagnosticReports` | 日志 / 崩溃报告 |
| `~/Library/Saved Application State` | 窗口状态 |
| `~/Library/Containers`、`~/Library/Group Containers` | 容器数据 |
| `~/Library/Application Scripts` | 应用脚本 |
| `~/Library/HTTPStorages`、`~/Library/Cookies`、`~/Library/WebKit` | 网络数据 |
| `~/Library/LaunchAgents` | 登录时启动项 |
| `~/Library/Autosave Information` | 自动保存 |
| `~/Library/Services`、`~/Library/PreferencePanes`、`~/Library/Internet Plug-Ins` | 扩展 |
| 每用户缓存目录与临时目录（`confstr(_CS_DARWIN_USER_CACHE_DIR)` / `_CS_DARWIN_USER_TEMP_DIR`） | 系统临时缓存 |
| 主目录 `~` 的一级隐藏项（`.` 开头） | 隐藏文件 |
| `~/.config`、`~/.cache`、`~/.local/share` 的一级子项 | 隐藏文件 |

系统级（通常需要管理员密码）：

| 位置 | 类别名 |
|---|---|
| `/Library/Application Support`、`/Library/Caches`、`/Library/Logs`、`/Library/Preferences` | 系统级数据 |
| `/Library/LaunchAgents`、`/Library/LaunchDaemons` | 后台服务 |
| `/Library/PrivilegedHelperTools` | 特权帮助程序 |
| `/private/var/db/receipts` | 安装记录 |

每个位置只看**一级**子项（不递归）：判断的是子项的名字；命中后整个子项（文件或文件夹）作为一条。位置不存在或无权读取 → 跳过。

### 3.3 匹配规则（纯函数 `LeftoverMatcher`）

输入：候选项的文件名、所在位置的种类、软件的标识（§3.1）。输出：确定相关 / 可能相关 / 不相关。比较一律不区分大小写；文件名先去掉已知后缀（`.plist`、`.savedState`、`.binarycookies`、`.bom`、`.log`、`.crash`、`.ips`、`.diag`）再比较。

确定相关（满足任一）：
1. 名字等于 bundle id，或以 `bundle id + "."` 开头（`com.x.App.helper`、`com.x.App.plist`）。
2. 名字以 `"." + bundle id` 结尾或包含 `"." + bundle id + "."`（Group Containers 的 `TEAMID.com.x.App`、ByHost 的 `com.x.App.UUID`）。
3. 位置的种类是"按软件名建文件夹"（Application Support、Caches、Logs、Saved Application State、HTTPStorages、WebKit、Application Scripts、Autosave Information、每用户缓存 / 临时目录，以及系统级的 Application Support、Caches、Logs），且名字**完全等于**某个名称变体。
4. 崩溃报告：名字以 `名称变体 + "_"` 或 `名称变体 + "-"` 开头。

可能相关（不满足上面、满足任一）：
1. 名字包含 bundle id 的最后一段（长度 ≥ 4），或包含某个名称变体（长度 ≥ 4）。
2. 隐藏文件位置：名字去掉开头的 `.` 后等于某个名称变体（`~/.docker`）。
3. 名字等于厂商片段（`~/Library/Application Support/Tencent`）。

其余为不相关。受保护路径（§4.2）永远不相关。

## 4. 安全规则（全部有自动测试）

### 4.1 不可卸载的软件（`ProtectionRules`）

满足任一即受保护：路径在 `/System/` 下；bundle id 以 `com.apple.` 开头；bundle id 等于 MyKit 自己的；路径不是以 `.app` 结尾的目录；路径是符号链接。

### 4.2 不可移动的路径

- 任何 §3.2 的扫描位置**本身**（例如 `~/Library/Preferences`）、`~`、`~/Library`、`/Library`、`/`、`/Applications`、`/System` 及其下任何路径、`/usr`、`/bin`、`/sbin`、`/private/var/db` 本身。
- 执行前对每一条再做一次复核：路径必须是软件本体，或者其父目录恰好是某个 §3.2 扫描位置；路径经过标准化（解析 `..`），且不是符号链接指向的目标（对符号链接只移走链接本身）。复核不过 → 该项失败，原因"路径不在允许范围内"，其余照常。

### 4.3 只移到废纸篓

`Trasher` 只有两条执行路径：`FileManager.trashItem`，以及（权限不足时）让访达执行"移到废纸篓"。代码里不出现 `removeItem`、`unlink`、`rm`。有一条测试扫描模块源码确保这一点。

## 5. 执行与权限

| 情况 | 处理 |
|---|---|
| 当前用户可写 | `FileManager.trashItem(at:resultingItemURL:)` |
| 权限不足（App Store 软件、系统级目录、安装记录） | 通过 AppleScript 让访达执行 `delete POSIX file …`（访达会弹系统的管理员密码框）。同一次卸载里需要访达处理的项合并成一次调用，用户只输一次密码 |
| macOS 的"App 管理"保护拦截（移动其他软件的本体被拒绝） | 结果里该项标为失败，并显示引导：系统设置 → 隐私与安全性 → App 管理，打开 MyKit；附「打开系统设置」按钮 |
| 首次让访达执行 | 系统会询问是否允许 MyKit 控制访达（自动化授权）；被拒绝 → 对应项失败，提示到 隐私与安全性 → 自动化 里打开 |
| 读取 `~/Library/Containers` 等受保护目录被拒绝 | 该位置跳过；清单底部提示"部分位置无权读取，授予'完全磁盘访问权限'后可以找得更全"，附「打开系统设置」按钮（不强制） |
| 目标软件仍在运行 | §2.4 第 1 步 |

`Info.plist` 需要增加 `NSAppleEventsUsageDescription`（"MyKit 需要请访达把需要管理员权限的文件移到废纸篓"）。

以上授权的实际表现只能在真机上验证，列入验收清单；实现阶段根据实测调整文案与回退顺序。

## 6. 架构

新增 Target `UninstallerModule`（依赖 `Core`），实现 `AppModule`（菜单项「卸载软件…」，无设置页）。

| 单元 | 职责 | 测试 |
|---|---|---|
| `AppIdentity` | 从 `.app` 读出 bundle id、名称、版本；派生名称变体与厂商片段 | ✅ 用临时目录里伪造的 `.app` |
| `ProtectionRules` | §4.1、§4.2 | ✅ |
| `InstalledAppScanner` | 列出软件（注入根目录列表，测试用临时目录） | ✅ |
| `ScanLocation` | §3.2 的位置表：路径、类别名、种类（按 id / 按名称 / 隐藏文件 / 系统级） | ✅ |
| `LeftoverMatcher` | §3.3 纯函数 | ✅ 重点：大量正反例，含真实世界的命名（TEAMID 前缀、ByHost、savedState、崩溃报告、短名、厂商黑名单） |
| `LeftoverScanner` | 遍历位置的一级子项 → 匹配 → `LeftoverItem { url, category, confidence, needsAdmin, size? }`；位置根目录可注入 | ✅ 临时目录模拟 `~/Library`、主目录隐藏文件 |
| `SizeCalculator` | 目录的已分配大小（后台、可取消）；格式化 | ✅ |
| `Trasher` | 复核 + 执行；执行器是协议（`FileTrashing`），正式实现为 FileManager + 访达，测试注入假实现 | ✅ 不会真的移动任何文件；含复核拒绝、部分失败、需要管理员项的合并 |
| `NoPermanentDeleteTests` | 扫描模块源码，确保没有永久删除的调用 | ✅ |
| `UninstallerViewModel` | 列表、搜索、排序、选择、勾选、汇总、执行状态机 | ✅ 注入假的扫描器 / 执行器 |
| `UninstallerWindowController` + SwiftUI 视图 | 窗口、拖放、确认框、结果 | 手动 |
| `UninstallerModule` | `AppModule` 接线 | ✅ 身份与菜单项 |

并发：扫描与大小计算在后台任务里做，结果回到主线程；切换选中的软件时取消上一个扫描。

轻量：没有常驻对象、定时器或后台监视；窗口关闭即释放（图标、大小缓存、扫描结果）。

## 7. 测试

自动化（Swift Testing）：§6 标 ✅ 的全部单元。所有文件系统测试只在临时目录里进行；`Trasher` 的测试全部使用假执行器；**任何测试都不会移动或删除真实文件**。

手动验收清单（实现计划最后一个任务逐条列出，面向非开发者），建议用一个不重要的小软件（例如先装一个免费小工具）来验证：列表与图标 / 大小 / 搜索 / 排序；系统软件不在列表里、拖入系统软件被拒绝；选中后清单分组正确、隐藏文件出现在"可能相关"里；全选 / 只选确定相关；在访达中显示；软件正在运行时的提示与退出；确认框；移到废纸篓后在废纸篓里能看到、能放回原处；"App 管理"授权提示与引导；App Store 软件经访达弹密码框；拒绝授权时的失败提示；窗口关闭后内存回落；其余功能（剪切板、截图、监控）不受影响。
