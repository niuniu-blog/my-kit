# MyKit 设计文档：系统监控模块（CPU、内存）

日期：2026-09-21
状态：已实现（实现计划：`docs/superpowers/plans/2026-09-21-mykit-system-monitor.md`）
前置：外壳 + 剪切板、截图（一期、二期）均已实现并合并到 main

## 1. 目标与范围

在 MyKit 里增加系统监控：菜单栏上常驻显示 CPU 和内存占用，点开菜单能看到"谁最吃资源"。要求轻量、不依赖外部工具、无需任何授权。

### 已确认的决策

| 项 | 决策 |
|---|---|
| 监控项 | CPU、内存（用户只要这两项） |
| 显示位置 | 菜单栏 MyKit 图标旁直接显示文字 `CPU 12%  内存 63%`；可在设置里关掉 |
| 进程排行 | 点开菜单后，CPU、内存各列出前 5 名软件（带图标、辅助进程合并到所属软件） |
| 数据来源 | 直接读 macOS 内核接口：`host_processor_info`、`host_statistics64`、`proc_listallpids` / `proc_pid_rusage` / `proc_pidpath`。不调用 `top` / `ps` 等外部命令，不联网，无第三方库 |
| 单软件 CPU 百分比 | 与"活动监视器"一致：按单个核心计，一个软件占满一个核心 = 100%，可超过 100% |

### 已在本机验证（macOS 27，仅 CLT）

- 上述接口均可编译、无需授权；总 CPU、内存数值合理。
- 960 个进程中 615 个可读：属于 root 的系统进程（WindowServer、kernel_task 等）读不到 → 不参与排行；用户自己打开的软件全部可读。
- 按 `.app` 归组可行（Chrome 的辅助进程合并为"Google Chrome"）。
- 采样一遍全部进程约 8 ms。

### 不做

网速 / 磁盘 / 温度 / 电池 / 风扇、历史曲线、结束进程、占用过高时的通知或弹窗、每核心 CPU、内存压力等级。

## 2. 用户可见的行为

### 2.1 菜单栏

- MyKit 图标右侧显示 `CPU 12%  内存 63%`，等宽数字字体（`monospacedDigitSystemFont`，12pt），数值变化时宽度不抖动。
- 默认每 2 秒刷新。
- 某一项 ≥ 85% 时，该项的数字显示为红色（`systemRed`）；其余为默认菜单栏文字颜色。
- 图标的三种状态（正常 / 暂停记录变灰 / ⚠️ 授权丢失）不变，文字跟在图标后面。
- 设置里关掉"在菜单栏显示"后只剩图标（此时不再每 2 秒采样，见 §4）。

### 2.2 菜单

监控部分位于菜单最顶部，其后是分隔线，再后面是原有的菜单项。

```
┌────────────────────────────────────────┐
│ CPU   42%      用户 35%   系统 7%       │
│   🌐 Google Chrome             28.4%   │
│   …（共 5 行）                          │
│ 内存  63%      10.1 / 16 GB            │
│   💻 IntelliJ IDEA            3.2 GB   │
│   …（共 5 行）                          │
│ 打开活动监视器…                         │
│ ────────────────────────────────────── │
│ 打开剪切板                              │
│ …                                      │
└────────────────────────────────────────┘
```

- 两个标题行和 10 个排行行是自定义视图的菜单项（不可点击、不高亮）；菜单打开期间实时更新。
- 菜单打开的瞬间：立即采样一次 → 内存榜立刻显示；CPU 榜需要两次采样的差值，第一次采样后显示"正在统计…"，约 1 秒后做第二次采样并显示；此后按刷新间隔更新。菜单关闭后停止进程采样并丢弃样本。
- 排行行：软件图标（16pt）+ 名称（过长截断）+ 右对齐的数值。不足 5 个时只显示实际数量。
- 数值格式：CPU 保留 1 位小数（`28.4%`）；内存 ≥ 1 GB 显示 `3.2 GB`（1 位小数），否则 `850 MB`（整数）；总内存 `10.1 / 16 GB`。1 GB = 1024³ 字节。
- 「打开活动监视器…」：启动 `/System/Applications/Utilities/Activity Monitor.app`。

### 2.3 偏好设置「系统监控」一栏

- 开关：在菜单栏显示 CPU / 内存（默认开）。
- 刷新间隔：1 秒 / 2 秒 / 5 秒（默认 2 秒）。改动立即生效。

## 3. 计算规则

### 3.1 总 CPU

`host_processor_info(PROCESSOR_CPU_LOAD_INFO)` 给出每个核心的 user / system / idle / nice 累计 tick（32 位无符号，会回绕）。把所有核心相加得到一份快照；两份快照相减（按 32 位回绕逐核心求差后再相加）：

- 用户% = (Δuser + Δnice) / Δtotal，系统% = Δsystem / Δtotal，总% = 用户% + 系统%。
- Δtotal = 0（两次采样太近）时沿用上一次的结果。第一份快照之前显示 `--`。

### 3.2 内存

`host_statistics64(HOST_VM_INFO64)`：

- 已用 = (internal_page_count − purgeable_count + wire_count + compressor_page_count) × 页大小（与"活动监视器"的"已使用内存"口径一致）；internal < purgeable 时该项按 0 计。
- 总量 = `ProcessInfo.physicalMemory`；百分比 = 已用 / 总量，夹在 0…100。

### 3.3 进程排行

- 采样：`proc_listallpids` → 对每个 pid 调 `proc_pid_rusage(RUSAGE_INFO_V4)` 取 `ri_user_time + ri_system_time`（mach 时间单位，用 `mach_timebase_info` 换算成纳秒）与 `ri_phys_footprint`；`proc_pidpath` 取可执行文件路径。读取失败的 pid 跳过。
- 归组：路径里含 `.app/` → 取**最外层**的 `.app` 包作为一组（键 = 包路径，名称 = 包的本地化显示名，图标 = 包图标）；否则按可执行文件名归组（键与名称 = 文件名，图标 = 通用可执行文件图标）；路径为空 → 跳过。MyKit 自己也参与排行。
- 单软件 CPU% = Σ(该组各 pid 的 Δ纳秒) / (两次采样的时间间隔纳秒) × 100。只统计两次采样里都存在、且 CPU 时间没有变小的 pid（变小说明 pid 被回收复用）。
- 单软件内存 = Σ(该组各 pid 的 footprint)。
- 各取前 5；CPU 榜过滤掉 < 0.1% 的项；数值相同按名称排序，保证顺序稳定。

## 4. 采样调度（"轻量"的落实）

| 场景 | 行为 |
|---|---|
| 菜单栏显示开启 | 一个按刷新间隔运行的定时器（容差 20%），每次只读两个内核计数器（微秒级） |
| 菜单栏显示关闭、菜单未打开 | 不运行任何定时器，零开销 |
| 菜单打开期间 | 总数与进程排行一起按刷新间隔更新（定时器加在 `.common` 模式，菜单跟踪期间也能触发）；首次 CPU 榜在打开后约 1 秒给出 |
| 菜单关闭 | 停止进程采样、丢弃样本；是否继续读总数取决于菜单栏显示开关 |

图标缓存：按组键缓存 `NSImage`，模块生命周期内有效（数量级为几十个 16pt 图标）。

## 5. 架构

新增 Target `SystemMonitorModule`（依赖 `Core`），实现 `AppModule`。

### 5.1 Core / 外壳的改动

| 改动 | 说明 |
|---|---|
| `AppModule` 增加 `menuWillOpen()` / `menuDidClose()`（默认空实现） | 让模块知道菜单的开关时机 |
| `ModuleRegistry` 增加 `menuWillOpen()` / `menuDidClose()` | 转发给所有已启动的模块（已测） |
| `StatusBarController` | 状态项长度改为可变；新增 `setTitle(_ attributed: NSAttributedString?)`（图标在左、文字在右）；成为菜单的 delegate 并回调 `onMenuWillOpen` / `onMenuDidClose` |
| `AppDelegate` | **最先**注册 `SystemMonitorModule`（它的菜单项因此排在最上面，其后由 `StatusBarController` 加分隔线）；接线标题更新与菜单开关回调 |

`StatusBarController` 目前把所有模块的菜单项连续排列、最后才加分隔线。改为：每个模块的菜单项之后加一条分隔线（模块没有菜单项则不加）。

### 5.2 SystemMonitorModule 的单元

| 单元 | 职责 | 测试 |
|---|---|---|
| `CPUTicks` / `CPULoad` | 每核心 tick 快照；`CPULoad.between(_:_:)` 纯函数，含 32 位回绕、核心数变化（返回 nil）、Δtotal = 0（返回 nil） | ✅ |
| `MemoryUsage` | `MemoryUsage.from(internal:purgeable:wired:compressed:pageSize:total:)` 纯函数 | ✅ |
| `HostStatsReader` | 上述两个内核调用的薄包装，返回 `CPUTicks?` / `MemoryUsage?` | 冒烟测试：能读到、数值在合理范围 |
| `ProcessSample` / `ProcessSampler` | `ProcessSample { pid, cpuNanoseconds, footprint, path }`；`ProcessSampler.sampleAll() -> (samples, timestamp)` 薄包装 | 冒烟测试：结果非空、包含当前进程 |
| `ProcessGrouping` | 纯函数：路径 → `AppGroup { key, fallbackName, bundlePath? }`（最外层 `.app`、无 `.app`、空路径） | ✅ |
| `TopProcesses` | 纯函数：两份样本 + 时间间隔 → CPU 榜；一份样本 → 内存榜；排序、过滤、pid 复用、稳定顺序 | ✅ |
| `MonitorFormat` | 纯函数：百分比、内存大小、`10.1 / 16 GB`、菜单栏标题的分段（文字 + 是否告警） | ✅ |
| `MonitorSettings` | UserDefaults：`monitor.showInMenuBar`（默认 true）、`monitor.interval`（1 / 2 / 5，非法值回退 2） | ✅ |
| `MonitorEngine` | 调度（§4）：持有读取器（可注入假实现）、定时器、上一份快照；输出 `onTotals`、`onTopLists` 回调；`setMenuOpen(_:)`、`applySettings()`。核心逻辑 `tick()` 可直接调用 | ✅ 注入假读取器：首次无 CPU 值、第二次有值；菜单开关对进程采样的影响；关闭显示且菜单关闭时不采样 |
| `AppIconCache` | 组键 → 图标 / 显示名 | 手动 |
| `MonitorMenuViews` | 标题行视图、排行行视图（AppKit，固定宽度 300pt） | 手动 |
| `MonitorSettingsView` | SwiftUI 设置页（用 `@AppStorage`，改动后通知引擎） | 手动 |
| `SystemMonitorModule` | `AppModule`：菜单项（2 个标题行 + 10 个排行行 + 「打开活动监视器…」）、`onMenuBarTitleChange` 回调、`menuWillOpen/menuDidClose`、设置页 | ✅ 身份、菜单项数量与标题 |

## 6. 错误处理

| 情况 | 处理 |
|---|---|
| 内核调用失败 | 该项显示 `--`，下次照常重试；不弹窗、不刷日志（每种错误只记一次日志） |
| 某个 pid 读不到（权限 / 已退出） | 跳过 |
| 图标或显示名取不到 | 用通用图标 / 文件名 |
| 活动监视器打不开 | Toast「无法打开活动监视器」 |

## 7. 测试

自动化（Swift Testing）：§5.2 标 ✅ 的全部单元，外加 `ModuleRegistry` 的菜单开关转发。测试不依赖真实系统负载：纯函数用构造的数据；引擎用假读取器和手动 `tick()`；两个读取器各一个冒烟测试。

手动验收清单（实现计划最后一个任务逐条列出，面向非开发者）：菜单栏文字出现且约 2 秒一变、数字不抖动；打开一个吃 CPU 的软件后数字上升、排行榜第一名正确（对照"活动监视器"）；≥ 85% 变红；菜单打开时内存榜立即出现、CPU 榜约 1 秒后出现并持续刷新；图标和中文软件名正确、Chrome 的辅助进程已合并；「打开活动监视器…」；设置里关掉显示 / 改间隔立即生效；剪切板、截图、图标的暂停 / ⚠️ 状态不受影响；MyKit 自身的 CPU 占用在"活动监视器"里平时接近 0。

## 8. 实现阶段的细化（写计划并编译验证时确定）

1. ≥ 85% 的告警按**显示出来的整数**判断：84.5 显示为"85%"并变红，所见即所判。
2. CPU 榜的 pid 复用保护除了"CPU 时间没有变小"，还要求两次采样的可执行文件路径相同。
3. `MonitorEngine`：`menuDidOpen() async` 立即采样一次，再在可注入的 `firstCPUListDelay`（默认约 1 秒）之后采样第二次；另有 `setMenuOpen`、`refreshTotals()`、`wantsTimer`、`lastTotals`。
4. 采样完全停止（菜单栏显示关闭且菜单关闭）时丢弃 CPU 基准快照，所以重新开启后第一个间隔内 CPU 显示 `--`。
5. 菜单栏标题以一个空格开头，与图标留出间距；只有告警的那一段设置颜色，其余保持系统默认（深色 / 浅色菜单栏都正确）。
6. 分隔线逻辑放在 `Core`：`ModuleRegistry.menuItemsWithSeparators`（已测），`StatusBarController` 直接使用。
7. `SystemMonitorModule.currentMenuBarTitle` 用于初始化标题（状态栏在模块启动之后才创建）。
8. 监控模块最先注册（菜单项在最上面），但在偏好设置里排在最后。
9. 每次打开菜单两个榜都先重置为"正在统计…"；CPU 榜为空显示"暂无明显占用"，内存榜为空显示"暂无数据"。
10. `HostStatsReader` 缓存 `mach_host_self()`（避免每次调用泄漏一个端口引用），页大小用 `host_page_size`。
11. `MonitorSettings` 的 setter 自己发变更通知；设置变化后模块立即重读一次总数。
12. 菜单视图尺寸：宽 300pt，标题行 24pt，排行行 20pt，图标 16pt（`AppIconCache`，已测）。
13. 装机后实测并优化了 MyKit 自身的空闲开销（用 `ps` 的累计 CPU 时间和 `sample` 定位）：优化前约 1.1%（单核），其中系统监控本身只占约 0.1%，其余来自原有的定时任务。两处改动：(a) 菜单栏标题内容（文字 + 颜色）没变时不再通知 `StatusBarController`，避免无谓的文字重排（已测）；(b) `AccessibilityWatcher` 改为自适应间隔 —— 未授权时每 1 秒检查，已授权后每 5 秒（`currentInterval`，已测）。优化后实测约 0.6%（单核），折合整机约 0.05%；常驻内存约 54 MB。
14. 排查提示：单元测试里的假读取器会故意返回失败，测试进程（`swiftpm-testing-helper`）因此会以同一个日志分类写出"读取 CPU 统计失败"。查看 App 自己的日志要加 `process == "MyKit"` 过滤。
