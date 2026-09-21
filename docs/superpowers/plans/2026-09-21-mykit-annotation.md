# MyKit 截图第二期 —— 标注工具 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在截图遮罩的工具条上增加九种标注工具（方框、椭圆、箭头、直线、画笔、荧光笔、文字、马赛克、序号）和撤销 / 重做；复制 / 保存 / 贴图输出带标注的图，文字识别用"原图 + 仅马赛克"。

**Architecture:** 矢量标注列表：每个标注是一条值类型数据（选区内坐标），`AnnotationModel` 是纯状态机（鼠标事件 → 标注、撤销 / 重做、序号计数、选区锁定），`AnnotationRenderer` 用同一套 CoreGraphics 代码完成屏幕实时绘制和导出合成（含马赛克像素化）。`OverlayView` 在选区锁定时把鼠标事件交给 `AnnotationModel`，工具条和样式栏只反映 / 修改模型状态。全部在 `ScreenshotModule` 内，不改 `Core` 和其他模块。

**Tech Stack:** Swift 6.4（语言模式 5）、AppKit、CoreGraphics、Swift Testing。无第三方依赖。

**Spec:** `docs/superpowers/specs/2026-09-21-mykit-annotation-design.md`

## Global Constraints

- 运行环境：macOS 27，只有 Command Line Tools，**没有 Xcode**。不要使用 `xcodebuild`、`.xcodeproj`、XCTest。
- 构建必须带 `--build-system native`（会有一条 deprecated 警告，忽略）。跑测试**只用** `scripts/test.sh`；直接 `swift test` 会报 `no such module 'Testing'`。
- 测试框架：Swift Testing（`import Testing`、`@Test`、`#expect`、`#require`）。
- **`#expect` 里不要写字面量算术**（如 `x == 1600 - 16` 会因类型推断失败而误报），先用 `let` 算好或直接写结果；`try` / `await` 的值同理先取出来再比较。
- **不要写 `@State`**（macOS 27 SDK 里是宏，CLT 下没有宏插件）；需要时用 `Core` 里的别名 `@ViewState`。同理不要用 `#Preview`、`@Entry`、`@Animatable`。本计划的界面全部是 AppKit，用不到它们。
- 最低系统 macOS 14；更高版本的 API 必须包在 `#available` 里。
- 不引入任何第三方依赖。Swift 语言模式 5；目标是零编译警告。
- 所有界面相关的类型在主线程使用；`NSView` 子类天然是 `@MainActor`。
- 不新增常驻对象、定时器或线程；马赛克缓存只活在一次截图会话里。
- 测试不能依赖"屏幕录制"授权，不能碰真实的系统剪切板、桌面、`UserDefaults.standard`（用 `UserDefaults(suiteName:)` 的临时域）。
- 所有面向用户的文案用简体中文。
- 终端是 zsh：查日志用 `/usr/bin/log`（`log` 是 zsh 内建命令）；zsh 数组下标从 1 开始。
- 每个任务结束时 `scripts/test.sh` 必须全绿、零警告，然后提交。
- 本计划修改已有文件时一律给出**完整的新文件内容**（整体替换）。动手前先确认工作区干净（`git status`），文件内容与计划写作时一致。

## File Structure

```
Sources/ScreenshotModule/
  AnnotationTool.swift          新增  九种工具：中文名、SF Symbol、是否有颜色
  AnnotationStyle.swift         新增  AnnotationColor（6 色）、AnnotationSize（3 档及各工具的线宽 / 字号 / 直径 / 方块）
  Annotation.swift              新增  一个标注 = kind（带几何）+ color + size
  AnnotationGeometry.swift      新增  Shift 约束、箭头头部、箭身终点（纯函数）
  AnnotationModel.swift         新增  纯状态机：工具、进行中的标注、已完成列表、撤销 / 重做、序号、locksSelection
  AnnotationSettings.swift      新增  记住颜色 / 粗细
  AnnotationRenderer.swift      新增  绘制 + 导出合成 + 马赛克；MosaicCache
  OverlayCancel.swift           新增  取消键的层级（纯函数）
  AnnotationStyleBar.swift      新增  样式栏：6 色 + 3 档
  ScreenshotSettings.swift      修改  增加 annotation（共用同一个 UserDefaults）
  SelectionModel.swift          修改  增加 isLocked
  DisplaySnapshot.swift         修改  CaptureResult.make 接收标注：image / ocrImage / annotationsDropped
  ToolbarPlacement.swift        修改  增加 styleBarOrigin
  CaptureAction.swift           修改  OverlayCommand 增加 undo / redo；OverlayKeyMap 增加 ⌘Z / ⇧⌘Z
  CaptureToolbar.swift          修改  工具按钮组 + 撤销 / 重做 + 原有操作
  OverlayView.swift             修改  鼠标事件分流、标注绘制、文字输入框、光标、样式栏
  CaptureOverlayController.swift 修改 OverlayPanel 让输入框拿到按键；undo / redo / 取消层级 / 带标注导出 / OCR 用 ocrImage
  ScreenshotActions.swift       修改  perform(_:result:) + 标注未合成的补充提示
  ScreenshotModule.swift        修改  改用 perform(_:result:)

Tests/ScreenshotModuleTests/
  AnnotationBasicsTests.swift   新增  工具 / 样式 / 几何
  AnnotationModelTests.swift    新增  状态机 + 设置
  AnnotationRendererTests.swift 新增  渲染后的像素检查
  OverlayCancelTests.swift      新增
  AnnotationUITests.swift       新增  工具条 / 样式栏 / OverlayView 的冒烟测试
  SelectionModelTests.swift / CaptureResultTests.swift / ToolbarPlacementTests.swift /
  OverlayKeyMapTests.swift / ScreenshotActionsTests.swift   修改（追加用例）

README.md                       修改  标注一节
```

任务顺序：1 数据与几何 → 2 状态机与设置 → 3 渲染 → 4 纯逻辑整合（选区锁定、带标注的成品、取消层级、样式栏位置）→ 5 界面 → 6 提示、使用说明、验收。

---
### Task 1: 标注的数据类型与几何计算

**Files:**
- Create: `Sources/ScreenshotModule/AnnotationTool.swift`, `Sources/ScreenshotModule/AnnotationStyle.swift`, `Sources/ScreenshotModule/Annotation.swift`, `Sources/ScreenshotModule/AnnotationGeometry.swift`
- Test: `Tests/ScreenshotModuleTests/AnnotationBasicsTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `public enum AnnotationTool: String, CaseIterable { case rectangle, ellipse, arrow, line, pen, highlighter, text, mosaic, number; var displayName: String; var symbolName: String; var usesColor: Bool }`（`allCases` 顺序 = 工具条顺序）
  - `public enum AnnotationColor: String, CaseIterable { case red, yellow, green, blue, black, white; var displayName; var components; func cgColor(alpha: CGFloat = 1) -> CGColor; var numberTextIsBlack: Bool }`
  - `public enum AnnotationSize: String, CaseIterable { case small, medium, large; var displayName; var strokeWidth /*2 4 6*/; var highlighterWidth /*12 18 24*/; var fontSize /*14 20 28*/; var mosaicBlock /*8 12 18*/; var numberDiameter /*22 28 36*/ }`
  - `public let annotationHighlighterAlpha: CGFloat /*0.4*/`
  - `public struct Annotation: Equatable { enum Kind { rectangle(CGRect), ellipse(CGRect), line(from:to:), arrow(from:to:), pen([CGPoint]), highlighter([CGPoint]), text(String, origin: CGPoint), mosaic(CGRect), number(Int, center: CGPoint) }; let kind; let color; let size; var isMosaic; var isNumber }`（几何为选区内坐标：选区左上角原点、y 向下、pt）
  - `public enum AnnotationGeometry { static func distance(_:_:); static func rect(from:to:square:) -> CGRect; static func snappedEndpoint(from:to:) -> CGPoint; static func arrowHeadLength(lineWidth:); static func arrowHead(from:to:lineWidth:) -> [CGPoint]; static func arrowShaftEnd(from:to:lineWidth:) -> CGPoint }`

- [ ] **Step 1: 写失败的测试**

`Tests/ScreenshotModuleTests/AnnotationBasicsTests.swift`:

```swift
import AppKit
import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct AnnotationToolTests {
    @Test func nineToolsInToolbarOrder() {
        #expect(AnnotationTool.allCases == [.rectangle, .ellipse, .arrow, .line, .pen, .highlighter, .text, .mosaic, .number])
    }

    @Test func everyToolHasAChineseNameAndAValidSymbol() {
        let names = AnnotationTool.allCases.map(\.displayName)
        #expect(names == ["方框", "椭圆", "箭头", "直线", "画笔", "荧光笔", "文字", "马赛克", "序号"])
        for tool in AnnotationTool.allCases {
            #expect(NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: nil) != nil, "\(tool.symbolName)")
        }
    }

    @Test func onlyMosaicHasNoColor() {
        #expect(!AnnotationTool.mosaic.usesColor)
        #expect(AnnotationTool.allCases.filter { !$0.usesColor } == [.mosaic])
    }
}

@Suite struct AnnotationStyleTests {
    @Test func sixColorsWithChineseNames() {
        #expect(AnnotationColor.allCases.map(\.displayName) == ["红", "黄", "绿", "蓝", "黑", "白"])
    }

    @Test func numberTextIsBlackOnLightColorsOnly() {
        #expect(AnnotationColor.allCases.filter(\.numberTextIsBlack) == [.yellow, .white])
    }

    @Test func cgColorCarriesComponentsAndAlpha() {
        let color = AnnotationColor.blue.cgColor(alpha: 0.4)
        let parts = color.components ?? []
        #expect(parts.count == 4)
        #expect(parts[0] == 0)
        #expect(parts[2] == 1)
        #expect(abs(parts[3] - 0.4) < 0.0001)
    }

    @Test func sizeMetricsPerTool() {
        #expect(AnnotationSize.allCases.map(\.displayName) == ["细", "中", "粗"])
        #expect(AnnotationSize.allCases.map(\.strokeWidth) == [2, 4, 6])
        #expect(AnnotationSize.allCases.map(\.highlighterWidth) == [12, 18, 24])
        #expect(AnnotationSize.allCases.map(\.fontSize) == [14, 20, 28])
        #expect(AnnotationSize.allCases.map(\.mosaicBlock) == [8, 12, 18])
        #expect(AnnotationSize.allCases.map(\.numberDiameter) == [22, 28, 36])
    }

    @Test func annotationKnowsWhetherItIsMosaicOrNumber() {
        let mosaic = Annotation(kind: .mosaic(CGRect(x: 0, y: 0, width: 10, height: 10)), color: .red, size: .medium)
        let number = Annotation(kind: .number(1, center: .zero), color: .red, size: .medium)
        #expect(mosaic.isMosaic)
        #expect(!mosaic.isNumber)
        #expect(number.isNumber)
        #expect(!number.isMosaic)
    }
}

@Suite struct AnnotationGeometryTests {
    private func close(_ a: CGPoint, _ b: CGPoint, tolerance: CGFloat = 0.001) -> Bool {
        abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
    }

    @Test func rectIsNormalizedWhateverTheDragDirection() {
        let expected = CGRect(x: 10, y: 20, width: 30, height: 40)
        #expect(AnnotationGeometry.rect(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 40, y: 60), square: false) == expected)
        #expect(AnnotationGeometry.rect(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 10, y: 20), square: false) == expected)
    }

    @Test func shiftMakesASquareFollowingTheDragDirection() {
        let downRight = AnnotationGeometry.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 30), square: true)
        #expect(downRight == CGRect(x: 10, y: 10, width: 40, height: 40))
        let upLeft = AnnotationGeometry.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 90, y: 40), square: true)
        #expect(upLeft == CGRect(x: 40, y: 40, width: 60, height: 60))
    }

    @Test func snappingKeepsLengthAndRoundsAngleTo45Degrees() {
        let start = CGPoint(x: 100, y: 100)
        // 略微偏离水平 → 吸附到水平，长度不变
        let nearlyHorizontal = CGPoint(x: 200, y: 108)
        let horizontalLength = AnnotationGeometry.distance(start, nearlyHorizontal)
        let horizontal = AnnotationGeometry.snappedEndpoint(from: start, to: nearlyHorizontal)
        #expect(close(horizontal, CGPoint(x: start.x + horizontalLength, y: start.y)))
        // 略微偏离竖直向上 → 吸附到竖直
        let nearlyVertical = CGPoint(x: 95, y: 0)
        let verticalLength = AnnotationGeometry.distance(start, nearlyVertical)
        let vertical = AnnotationGeometry.snappedEndpoint(from: start, to: nearlyVertical)
        #expect(close(vertical, CGPoint(x: start.x, y: start.y - verticalLength)))
        // 接近 45°
        let diagonal = AnnotationGeometry.snappedEndpoint(from: start, to: CGPoint(x: 160, y: 170))
        #expect(abs((diagonal.x - 100) - (diagonal.y - 100)) < 0.001)
        // 起点终点重合：原样返回
        #expect(AnnotationGeometry.snappedEndpoint(from: start, to: start) == start)
    }

    @Test func arrowHeadSizeFollowsLineWidth() {
        #expect(AnnotationGeometry.arrowHeadLength(lineWidth: 2) == 14)
        #expect(AnnotationGeometry.arrowHeadLength(lineWidth: 6) == 30)
    }

    @Test func arrowHeadIsSymmetricAroundTheShaft() {
        let head = AnnotationGeometry.arrowHead(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 50), lineWidth: 4)
        #expect(head.count == 3)
        #expect(head[0] == CGPoint(x: 100, y: 50))
        let length: CGFloat = 22
        #expect(abs(AnnotationGeometry.distance(head[0], head[1]) - length) < 0.001)
        #expect(abs(AnnotationGeometry.distance(head[0], head[2]) - length) < 0.001)
        #expect(abs(head[1].x - head[2].x) < 0.001)                   // 两翼左右对称
        #expect(abs((head[1].y - 50) + (head[2].y - 50)) < 0.001)
        #expect(head[1].x < 100)
    }

    @Test func arrowShaftStopsBeforeTheTip() {
        let end = AnnotationGeometry.arrowShaftEnd(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), lineWidth: 4)
        #expect(end.x > 70)
        #expect(end.x < 100)
        #expect(end.y == 0)
        // 箭头比头部还短：箭身长度为 0
        let tiny = AnnotationGeometry.arrowShaftEnd(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 5, y: 0), lineWidth: 4)
        #expect(tiny == CGPoint(x: 0, y: 0))
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'AnnotationTool' in scope`

- [ ] **Step 3: 写实现（四个新文件）**

`Sources/ScreenshotModule/AnnotationTool.swift`:

```swift
import Foundation

/// 九种标注工具。allCases 的顺序就是工具条上从左到右的顺序。
public enum AnnotationTool: String, CaseIterable, Equatable, Sendable {
    case rectangle, ellipse, arrow, line, pen, highlighter, text, mosaic, number

    /// 鼠标悬停在按钮上时显示的中文名
    public var displayName: String {
        switch self {
        case .rectangle: return "方框"
        case .ellipse: return "椭圆"
        case .arrow: return "箭头"
        case .line: return "直线"
        case .pen: return "画笔"
        case .highlighter: return "荧光笔"
        case .text: return "文字"
        case .mosaic: return "马赛克"
        case .number: return "序号"
        }
    }

    /// 按钮图标（SF Symbols）
    public var symbolName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .pen: return "pencil"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .mosaic: return "checkerboard.rectangle"
        case .number: return "1.circle"
        }
    }

    /// 马赛克没有颜色可选：选中它时样式栏只显示粗细（= 方块大小）
    public var usesColor: Bool {
        self != .mosaic
    }
}
```

`Sources/ScreenshotModule/AnnotationStyle.swift`:

```swift
import CoreGraphics

/// 6 种预设颜色。
public enum AnnotationColor: String, CaseIterable, Equatable, Sendable {
    case red, yellow, green, blue, black, white

    public var displayName: String {
        switch self {
        case .red: return "红"
        case .yellow: return "黄"
        case .green: return "绿"
        case .blue: return "蓝"
        case .black: return "黑"
        case .white: return "白"
        }
    }

    /// 0…1 的 RGB 分量
    public var components: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        switch self {
        case .red: return (1.0, 0.23, 0.19)
        case .yellow: return (1.0, 0.8, 0.0)
        case .green: return (0.2, 0.78, 0.35)
        case .blue: return (0.0, 0.48, 1.0)
        case .black: return (0.0, 0.0, 0.0)
        case .white: return (1.0, 1.0, 1.0)
        }
    }

    public func cgColor(alpha: CGFloat = 1) -> CGColor {
        let rgb = components
        return CGColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    }

    /// 序号圆里的数字：底色浅（白、黄）时用黑字，其余用白字
    public var numberTextIsBlack: Bool {
        self == .white || self == .yellow
    }
}

/// 3 档粗细。同一个档位在不同工具上的含义不同。
public enum AnnotationSize: String, CaseIterable, Equatable, Sendable {
    case small, medium, large

    public var displayName: String {
        switch self {
        case .small: return "细"
        case .medium: return "中"
        case .large: return "粗"
        }
    }

    /// 方框 / 椭圆 / 直线 / 箭头 / 画笔的线宽（pt）
    public var strokeWidth: CGFloat {
        switch self {
        case .small: return 2
        case .medium: return 4
        case .large: return 6
        }
    }

    /// 荧光笔的线宽（pt）
    public var highlighterWidth: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 18
        case .large: return 24
        }
    }

    /// 文字的字号（pt）
    public var fontSize: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 20
        case .large: return 28
        }
    }

    /// 马赛克方块的边长（pt）
    public var mosaicBlock: CGFloat {
        switch self {
        case .small: return 8
        case .medium: return 12
        case .large: return 18
        }
    }

    /// 序号圆的直径（pt）
    public var numberDiameter: CGFloat {
        switch self {
        case .small: return 22
        case .medium: return 28
        case .large: return 36
        }
    }
}

/// 荧光笔的不透明度
public let annotationHighlighterAlpha: CGFloat = 0.4
```

`Sources/ScreenshotModule/Annotation.swift`:

```swift
import CoreGraphics

/// 一个标注。几何数据用"选区内坐标"：选区左上角为原点、y 向下、单位 pt。
/// 只是一小段数据：屏幕上实时绘制，导出时再合成到图上；撤销 = 去掉最后一条。
public struct Annotation: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case rectangle(CGRect)
        case ellipse(CGRect)
        case line(from: CGPoint, to: CGPoint)
        case arrow(from: CGPoint, to: CGPoint)
        case pen([CGPoint])
        case highlighter([CGPoint])
        /// origin 是文字左上角
        case text(String, origin: CGPoint)
        case mosaic(CGRect)
        case number(Int, center: CGPoint)
    }

    public let kind: Kind
    public let color: AnnotationColor
    public let size: AnnotationSize

    public init(kind: Kind, color: AnnotationColor, size: AnnotationSize) {
        self.kind = kind
        self.color = color
        self.size = size
    }

    public var isMosaic: Bool {
        if case .mosaic = kind { return true }
        return false
    }

    public var isNumber: Bool {
        if case .number = kind { return true }
        return false
    }
}
```

`Sources/ScreenshotModule/AnnotationGeometry.swift`:

```swift
import CoreGraphics
import Foundation

/// 标注用到的几何计算。纯函数。
public enum AnnotationGeometry {
    public static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    /// 由拖动的起点和当前点得到矩形。square = true（按住 Shift）时取较长的一边做正方形，方向跟随拖动方向。
    public static func rect(from start: CGPoint, to current: CGPoint, square: Bool) -> CGRect {
        var dx = current.x - start.x
        var dy = current.y - start.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        return CGRect(x: min(start.x, start.x + dx), y: min(start.y, start.y + dy), width: abs(dx), height: abs(dy))
    }

    /// 按住 Shift 画直线 / 箭头：方向吸附到最近的 45° 倍数，长度不变。
    public static func snappedEndpoint(from start: CGPoint, to current: CGPoint) -> CGPoint {
        let length = distance(start, current)
        guard length > 0 else { return current }
        let step = CGFloat.pi / 4
        let angle = (atan2(current.y - start.y, current.x - start.x) / step).rounded() * step
        return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
    }

    /// 箭头头部的长度：线宽 × 4 + 6
    public static func arrowHeadLength(lineWidth: CGFloat) -> CGFloat {
        lineWidth * 4 + 6
    }

    /// 箭头头部三角形的三个顶点：[尖端, 左翼, 右翼]。两翼与箭身夹角 ±28°。
    public static func arrowHead(from start: CGPoint, to tip: CGPoint, lineWidth: CGFloat) -> [CGPoint] {
        let length = arrowHeadLength(lineWidth: lineWidth)
        let angle = atan2(tip.y - start.y, tip.x - start.x)
        let spread = CGFloat(28) * .pi / 180
        let left = CGPoint(x: tip.x - cos(angle - spread) * length, y: tip.y - sin(angle - spread) * length)
        let right = CGPoint(x: tip.x - cos(angle + spread) * length, y: tip.y - sin(angle + spread) * length)
        return [tip, left, right]
    }

    /// 箭身画到哪里为止：停在头部三角形的底边附近，免得粗线从尖端两侧露出来。
    public static func arrowShaftEnd(from start: CGPoint, to tip: CGPoint, lineWidth: CGFloat) -> CGPoint {
        let total = distance(start, tip)
        let inset = arrowHeadLength(lineWidth: lineWidth) * cos(CGFloat(28) * .pi / 180) * 0.9
        guard total > inset else { return start }
        let ratio = (total - inset) / total
        return CGPoint(x: start.x + (tip.x - start.x) * ratio, y: start.y + (tip.y - start.y) * ratio)
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 252 tests in 44 suites passed`，零警告。如果 `everyToolHasAChineseNameAndAValidSymbol` 失败，说明某个 SF Symbol 名称在这台机器的系统里不存在 —— 换成同义的符号名并同步修改测试里的预期即可。

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenshotModule/AnnotationTool.swift Sources/ScreenshotModule/AnnotationStyle.swift Sources/ScreenshotModule/Annotation.swift Sources/ScreenshotModule/AnnotationGeometry.swift Tests/ScreenshotModuleTests/AnnotationBasicsTests.swift
git commit -m "feat(annotation): tools, colors, sizes, annotation data and geometry helpers"
```

---
### Task 2: 标注状态机与样式记忆

**Files:**
- Create: `Sources/ScreenshotModule/AnnotationModel.swift`, `Sources/ScreenshotModule/AnnotationSettings.swift`
- Modify: `Sources/ScreenshotModule/ScreenshotSettings.swift`（整体替换）
- Test: `Tests/ScreenshotModuleTests/AnnotationModelTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `AnnotationTool`、`AnnotationColor`、`AnnotationSize`、`Annotation`、`AnnotationGeometry`
- Produces:
  - `public struct AnnotationModel`：`init(color: AnnotationColor = .red, size: AnnotationSize = .medium)`；`tool: AnnotationTool?`（只读）；`var color`；`var size`；`items: [Annotation]`；`redoStack`；`inProgress: Annotation?`；`locksSelection: Bool`；`canUndo`；`canRedo`；`nextNumber: Int`；`mutating func toggleTool(_:)`；`deselectTool()`；`mouseDown(at:in:shift:) -> MouseDownResult`；`mouseDragged(to:shift:)`；`mouseUp(at:shift:)`；`placeText(_:at:)`；`undo()`；`redo()`；`reset()`
  - `AnnotationModel.MouseDownResult`：`.ignored` / `.beganDrag` / `.beginText(at: CGPoint)` / `.placedNumber`
  - `AnnotationModel.minimumDrag: CGFloat = 3`
  - `public struct AnnotationSettings { static let colorKey = "screenshot.annotation.color"; static let sizeKey = "screenshot.annotation.size"; init(defaults: UserDefaults = .standard); var color: AnnotationColor { get nonmutating set }; var size: AnnotationSize { get nonmutating set } }`
  - `ScreenshotSettings.annotation: AnnotationSettings`（共用同一个 UserDefaults）

所有坐标都是选区内坐标；`mouseDown` 的 `in:` 参数是选区尺寸（起点必须落在选区内，终点不夹取 —— 超出部分由渲染时的裁剪负责）。

- [ ] **Step 1: 写失败的测试**

`Tests/ScreenshotModuleTests/AnnotationModelTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct AnnotationModelTests {
    private let selection = CGSize(width: 400, height: 300)

    private func makeModel(tool: AnnotationTool?) -> AnnotationModel {
        var model = AnnotationModel()
        if let tool { model.toggleTool(tool) }
        return model
    }

    /// 完整的一次 按下-拖动-松开
    private func drag(_ model: inout AnnotationModel, from start: CGPoint, to end: CGPoint, shift: Bool = false) {
        _ = model.mouseDown(at: start, in: selection, shift: shift)
        model.mouseDragged(to: end, shift: shift)
        model.mouseUp(at: end, shift: shift)
    }

    // MARK: 工具选择与锁定

    @Test func startsWithRedMediumAndNoTool() {
        let model = AnnotationModel()
        #expect(model.tool == nil)
        #expect(model.color == .red)
        #expect(model.size == .medium)
        #expect(!model.locksSelection)
        #expect(!model.canUndo)
        #expect(!model.canRedo)
    }

    @Test func togglingSelectsSwitchesAndDeselects() {
        var model = AnnotationModel()
        model.toggleTool(.arrow)
        #expect(model.tool == .arrow)
        model.toggleTool(.pen)
        #expect(model.tool == .pen)
        model.toggleTool(.pen)
        #expect(model.tool == nil)
    }

    @Test func selectionIsLockedWhileAToolIsSelectedOrAnnotationsExist() {
        var model = makeModel(tool: .rectangle)
        #expect(model.locksSelection)
        drag(&model, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 40))
        model.deselectTool()
        #expect(model.locksSelection)            // 没有工具，但有标注
        model.undo()
        #expect(!model.locksSelection)           // 全部撤销且没有工具：解除锁定
    }

    @Test func mouseDownIsIgnoredWithoutAToolOrOutsideTheSelection() {
        var noTool = AnnotationModel()
        #expect(noTool.mouseDown(at: CGPoint(x: 10, y: 10), in: selection, shift: false) == .ignored)

        var model = makeModel(tool: .rectangle)
        #expect(model.mouseDown(at: CGPoint(x: 500, y: 10), in: selection, shift: false) == .ignored)
        model.mouseDragged(to: CGPoint(x: 100, y: 100), shift: false)
        model.mouseUp(at: CGPoint(x: 100, y: 100), shift: false)
        #expect(model.items.isEmpty)
        #expect(model.inProgress == nil)
    }

    // MARK: 每种工具

    @Test func rectangleEllipseAndMosaicProduceNormalizedRects() {
        let expected = CGRect(x: 20, y: 30, width: 100, height: 50)
        for (tool, kind) in [
            (AnnotationTool.rectangle, Annotation.Kind.rectangle(expected)),
            (.ellipse, .ellipse(expected)),
            (.mosaic, .mosaic(expected)),
        ] {
            var model = makeModel(tool: tool)
            drag(&model, from: CGPoint(x: 120, y: 80), to: CGPoint(x: 20, y: 30))
            #expect(model.items == [Annotation(kind: kind, color: .red, size: .medium)])
        }
    }

    @Test func shiftConstrainsRectangleToSquare() {
        var model = makeModel(tool: .rectangle)
        drag(&model, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 110, y: 40), shift: true)
        #expect(model.items.first?.kind == .rectangle(CGRect(x: 10, y: 10, width: 100, height: 100)))
    }

    @Test func lineAndArrowKeepDirection() {
        var line = makeModel(tool: .line)
        drag(&line, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 200, y: 90))
        #expect(line.items.first?.kind == .line(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 200, y: 90)))

        var arrow = makeModel(tool: .arrow)
        drag(&arrow, from: CGPoint(x: 200, y: 90), to: CGPoint(x: 10, y: 10))
        #expect(arrow.items.first?.kind == .arrow(from: CGPoint(x: 200, y: 90), to: CGPoint(x: 10, y: 10)))
    }

    @Test func shiftSnapsArrowToHorizontal() throws {
        var model = makeModel(tool: .arrow)
        drag(&model, from: CGPoint(x: 10, y: 100), to: CGPoint(x: 210, y: 110), shift: true)
        guard case .arrow(_, let tip) = try #require(model.items.first).kind else {
            Issue.record("应该是箭头")
            return
        }
        #expect(abs(tip.y - 100) < 0.001)
        #expect(tip.x > 209)
    }

    @Test func penCollectsThePath() {
        var model = makeModel(tool: .pen)
        _ = model.mouseDown(at: CGPoint(x: 10, y: 10), in: selection, shift: false)
        model.mouseDragged(to: CGPoint(x: 20, y: 15), shift: false)
        model.mouseDragged(to: CGPoint(x: 20.2, y: 15.1), shift: false)     // 离上一个点不足 1pt：不记
        model.mouseDragged(to: CGPoint(x: 30, y: 30), shift: false)
        #expect(model.inProgress?.kind == .pen([CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 15), CGPoint(x: 30, y: 30)]))
        model.mouseUp(at: CGPoint(x: 30, y: 30), shift: false)
        #expect(model.items.count == 1)
        #expect(model.inProgress == nil)
    }

    @Test func highlighterWithShiftIsAStraightLine() {
        var model = makeModel(tool: .highlighter)
        _ = model.mouseDown(at: CGPoint(x: 10, y: 50), in: selection, shift: true)
        model.mouseDragged(to: CGPoint(x: 100, y: 58), shift: true)
        model.mouseUp(at: CGPoint(x: 200, y: 52), shift: true)
        #expect(model.items.first?.kind == .highlighter([CGPoint(x: 10, y: 50), CGPoint(x: 200, y: 52)]))
    }

    @Test func endPointsOutsideTheSelectionAreKeptAsIs() {
        // 拖出选区的部分由渲染时的裁剪负责，这里不夹取
        var model = makeModel(tool: .line)
        drag(&model, from: CGPoint(x: 390, y: 290), to: CGPoint(x: 600, y: 500))
        #expect(model.items.first?.kind == .line(from: CGPoint(x: 390, y: 290), to: CGPoint(x: 600, y: 500)))
    }

    @Test func tinyDragsAndSinglePointStrokesAreIgnored() {
        for tool in [AnnotationTool.rectangle, .ellipse, .line, .arrow, .mosaic] {
            var model = makeModel(tool: tool)
            drag(&model, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 51, y: 52))
            #expect(model.items.isEmpty, "\(tool)")
        }
        for tool in [AnnotationTool.pen, .highlighter] {
            var model = makeModel(tool: tool)
            _ = model.mouseDown(at: CGPoint(x: 50, y: 50), in: selection, shift: false)
            model.mouseUp(at: CGPoint(x: 50, y: 50), shift: false)
            #expect(model.items.isEmpty, "\(tool)")
        }
    }

    @Test func numberToolPlacesIncrementingNumbersImmediately() {
        var model = makeModel(tool: .number)
        #expect(model.mouseDown(at: CGPoint(x: 10, y: 10), in: selection, shift: false) == .placedNumber)
        #expect(model.mouseDown(at: CGPoint(x: 50, y: 10), in: selection, shift: false) == .placedNumber)
        #expect(model.items.map(\.kind) == [.number(1, center: CGPoint(x: 10, y: 10)), .number(2, center: CGPoint(x: 50, y: 10))])

        model.undo()
        #expect(model.nextNumber == 2)           // 撤销后编号回退
        _ = model.mouseDown(at: CGPoint(x: 90, y: 10), in: selection, shift: false)
        #expect(model.items.last?.kind == .number(2, center: CGPoint(x: 90, y: 10)))
    }

    @Test func numbersOnlyCountNumberAnnotations() {
        var model = makeModel(tool: .rectangle)
        drag(&model, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 60))
        model.toggleTool(.number)
        _ = model.mouseDown(at: CGPoint(x: 100, y: 100), in: selection, shift: false)
        #expect(model.items.last?.kind == .number(1, center: CGPoint(x: 100, y: 100)))
    }

    @Test func textToolAsksTheViewForAnEditorThenPlacesText() {
        var model = makeModel(tool: .text)
        #expect(model.mouseDown(at: CGPoint(x: 30, y: 40), in: selection, shift: false) == .beginText(at: CGPoint(x: 30, y: 40)))
        #expect(model.items.isEmpty)

        model.placeText("第一行\nsecond", at: CGPoint(x: 30, y: 40))
        #expect(model.items == [Annotation(kind: .text("第一行\nsecond", origin: CGPoint(x: 30, y: 40)), color: .red, size: .medium)])
    }

    @Test func blankTextProducesNothing() {
        var model = makeModel(tool: .text)
        model.placeText("  \n ", at: .zero)
        model.placeText("", at: .zero)
        #expect(model.items.isEmpty)
    }

    @Test func annotationsCarryTheCurrentColorAndSize() {
        var model = makeModel(tool: .line)
        model.color = .blue
        model.size = .large
        drag(&model, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50))
        #expect(model.items.first?.color == .blue)
        #expect(model.items.first?.size == .large)
    }

    // MARK: 撤销 / 重做 / 重置

    @Test func undoRedoAndNewAnnotationClearsRedo() {
        var model = makeModel(tool: .line)
        drag(&model, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 0))
        drag(&model, from: CGPoint(x: 0, y: 10), to: CGPoint(x: 50, y: 10))
        #expect(model.items.count == 2)

        model.undo()
        #expect(model.items.count == 1)
        #expect(model.canRedo)
        model.redo()
        #expect(model.items.count == 2)
        #expect(!model.canRedo)

        model.undo()
        drag(&model, from: CGPoint(x: 0, y: 20), to: CGPoint(x: 50, y: 20))      // 新标注
        #expect(!model.canRedo)
        #expect(model.items.count == 2)

        model.undo()
        model.undo()
        model.undo()                                                          // 多撤销一次也没事
        #expect(model.items.isEmpty)
    }

    @Test func switchingToolAbandonsTheStrokeInProgress() {
        var model = makeModel(tool: .pen)
        _ = model.mouseDown(at: CGPoint(x: 10, y: 10), in: selection, shift: false)
        model.mouseDragged(to: CGPoint(x: 40, y: 40), shift: false)
        model.toggleTool(.arrow)
        #expect(model.inProgress == nil)
        model.mouseUp(at: CGPoint(x: 40, y: 40), shift: false)
        #expect(model.items.isEmpty)
    }

    @Test func resetClearsEverythingButKeepsStyle() {
        var model = makeModel(tool: .line)
        model.color = .green
        model.size = .small
        drag(&model, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 0))
        model.undo()

        model.reset()

        #expect(model.tool == nil)
        #expect(model.items.isEmpty)
        #expect(!model.canRedo)
        #expect(!model.locksSelection)
        #expect(model.color == .green)
        #expect(model.size == .small)
    }
}

@Suite struct AnnotationSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsToRedMedium() {
        let settings = AnnotationSettings(defaults: makeDefaults())
        #expect(settings.color == .red)
        #expect(settings.size == .medium)
    }

    @Test func remembersChoices() {
        let defaults = makeDefaults()
        AnnotationSettings(defaults: defaults).color = .blue
        AnnotationSettings(defaults: defaults).size = .large
        #expect(AnnotationSettings(defaults: defaults).color == .blue)
        #expect(AnnotationSettings(defaults: defaults).size == .large)
    }

    @Test func unknownStoredValuesFallBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set("purple", forKey: AnnotationSettings.colorKey)
        defaults.set("huge", forKey: AnnotationSettings.sizeKey)
        #expect(AnnotationSettings(defaults: defaults).color == .red)
        #expect(AnnotationSettings(defaults: defaults).size == .medium)
    }

    @Test func screenshotSettingsShareTheSameDefaults() {
        let defaults = makeDefaults()
        ScreenshotSettings(defaults: defaults).annotation.color = .green
        #expect(AnnotationSettings(defaults: defaults).color == .green)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'AnnotationModel' in scope`

- [ ] **Step 3: 写实现**

`Sources/ScreenshotModule/AnnotationModel.swift`:

```swift
import CoreGraphics
import Foundation

/// 标注的全部交互逻辑。纯状态机：输入鼠标事件（选区内坐标），输出"已完成的标注 / 正在画的标注"。
/// 画好的标注不能再选中修改，只能撤销重画。
public struct AnnotationModel {
    /// mouseDown 之后界面要做什么
    public enum MouseDownResult: Equatable {
        /// 什么也没发生（没有选中工具，或起点不在选区内）
        case ignored
        /// 开始拖动；后续调用 mouseDragged / mouseUp
        case beganDrag
        /// 文字工具：界面应在这个位置（选区内坐标）放一个输入框，输入完成后调用 placeText
        case beginText(at: CGPoint)
        /// 序号工具：已经放好一个序号
        case placedNumber
    }

    /// 拖动距离不足这个值的方框 / 椭圆 / 直线 / 箭头 / 马赛克视为误点
    public static let minimumDrag: CGFloat = 3

    public private(set) var tool: AnnotationTool?
    public var color: AnnotationColor
    public var size: AnnotationSize
    public private(set) var items: [Annotation] = []
    public private(set) var redoStack: [Annotation] = []
    /// 正在拖动中的标注（还没松手）
    public private(set) var inProgress: Annotation?

    private var dragStart: CGPoint?
    private var strokePoints: [CGPoint] = []

    public init(color: AnnotationColor = .red, size: AnnotationSize = .medium) {
        self.color = color
        self.size = size
    }

    // MARK: 状态

    /// 有工具选中或已有标注时，选区不能再移动 / 改大小（标注画在固定位置上）。
    public var locksSelection: Bool {
        tool != nil || !items.isEmpty
    }

    public var canUndo: Bool { !items.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// 下一个序号 = 已有序号标注的个数 + 1，所以撤销一个序号后编号自动回退。
    public var nextNumber: Int {
        items.filter(\.isNumber).count + 1
    }

    // MARK: 工具

    /// 点工具按钮：选中；再点一次同一个：取消选中。
    public mutating func toggleTool(_ newTool: AnnotationTool) {
        abandonDrag()
        tool = (tool == newTool) ? nil : newTool
    }

    public mutating func deselectTool() {
        abandonDrag()
        tool = nil
    }

    // MARK: 鼠标（选区内坐标）

    public mutating func mouseDown(at point: CGPoint, in selectionSize: CGSize, shift: Bool) -> MouseDownResult {
        guard let tool, CGRect(origin: .zero, size: selectionSize).contains(point) else { return .ignored }
        abandonDrag()
        switch tool {
        case .text:
            return .beginText(at: point)
        case .number:
            commit(Annotation(kind: .number(nextNumber, center: point), color: color, size: size))
            return .placedNumber
        case .rectangle, .ellipse, .arrow, .line, .pen, .highlighter, .mosaic:
            dragStart = point
            strokePoints = [point]
            return .beganDrag
        }
    }

    public mutating func mouseDragged(to point: CGPoint, shift: Bool) {
        guard let tool, let start = dragStart else { return }
        if tool == .pen || (tool == .highlighter && !shift) {
            if let last = strokePoints.last, AnnotationGeometry.distance(last, point) >= 1 {
                strokePoints.append(point)
            }
        }
        inProgress = makeAnnotation(tool: tool, start: start, current: point, shift: shift)
    }

    public mutating func mouseUp(at point: CGPoint, shift: Bool) {
        guard tool != nil, let start = dragStart else { return }
        mouseDragged(to: point, shift: shift)
        let finished = inProgress
        abandonDrag()
        guard let finished else { return }

        switch finished.kind {
        case .pen(let points), .highlighter(let points):
            guard points.count >= 2 else { return }
        default:
            guard AnnotationGeometry.distance(start, point) >= Self.minimumDrag else { return }   // 误点
        }
        commit(finished)
    }

    /// 文字输入完成。空内容（或只有空白）不产生标注。origin 是文字左上角（选区内坐标）。
    public mutating func placeText(_ text: String, at origin: CGPoint) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        commit(Annotation(kind: .text(text, origin: origin), color: color, size: size))
    }

    // MARK: 撤销 / 重做

    public mutating func undo() {
        abandonDrag()
        guard let last = items.popLast() else { return }
        redoStack.append(last)
    }

    public mutating func redo() {
        abandonDrag()
        guard let last = redoStack.popLast() else { return }
        items.append(last)
    }

    /// 清除选区时调用：标注、重做栈、选中的工具全部清掉（颜色和粗细保留）。
    public mutating func reset() {
        abandonDrag()
        tool = nil
        items.removeAll()
        redoStack.removeAll()
    }

    // MARK: 内部

    private mutating func commit(_ annotation: Annotation) {
        items.append(annotation)
        redoStack.removeAll()          // 产生新标注后不能再重做
    }

    private mutating func abandonDrag() {
        dragStart = nil
        strokePoints = []
        inProgress = nil
    }

    private func makeAnnotation(tool: AnnotationTool, start: CGPoint, current: CGPoint, shift: Bool) -> Annotation? {
        let kind: Annotation.Kind
        switch tool {
        case .rectangle:
            kind = .rectangle(AnnotationGeometry.rect(from: start, to: current, square: shift))
        case .ellipse:
            kind = .ellipse(AnnotationGeometry.rect(from: start, to: current, square: shift))
        case .mosaic:
            kind = .mosaic(AnnotationGeometry.rect(from: start, to: current, square: shift))
        case .line:
            kind = .line(from: start, to: shift ? AnnotationGeometry.snappedEndpoint(from: start, to: current) : current)
        case .arrow:
            kind = .arrow(from: start, to: shift ? AnnotationGeometry.snappedEndpoint(from: start, to: current) : current)
        case .pen:
            kind = .pen(strokePoints)
        case .highlighter:
            kind = .highlighter(shift ? [start, current] : strokePoints)     // Shift：起点到当前点的直线
        case .text, .number:
            return nil
        }
        return Annotation(kind: kind, color: color, size: size)
    }
}
```

`Sources/ScreenshotModule/AnnotationSettings.swift`:

```swift
import Foundation

/// 记住上次用的标注颜色和粗细。
public struct AnnotationSettings {
    public static let colorKey = "screenshot.annotation.color"
    public static let sizeKey = "screenshot.annotation.size"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 未设置或存了不认识的值时为红色
    public var color: AnnotationColor {
        get { defaults.string(forKey: Self.colorKey).flatMap(AnnotationColor.init(rawValue:)) ?? .red }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.colorKey) }
    }

    /// 未设置或存了不认识的值时为"中"
    public var size: AnnotationSize {
        get { defaults.string(forKey: Self.sizeKey).flatMap(AnnotationSize.init(rawValue:)) ?? .medium }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.sizeKey) }
    }
}
```

整体替换（只增加了 `annotation` 属性，其余不变）：

`Sources/ScreenshotModule/ScreenshotSettings.swift`:

```swift
import Foundation

public struct ScreenshotSettings {
    public static let saveFolderKey = "screenshot.saveFolder"
    public static let autoTranslateKey = "screenshot.autoTranslate"

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

    /// 标注工具的颜色 / 粗细记忆，和本设置共用同一个 UserDefaults
    public var annotation: AnnotationSettings {
        AnnotationSettings(defaults: defaults)
    }

    /// 识别结果面板上"翻译成中文"的勾选状态：勾上后每次识别完自动翻译，直到取消。
    public var autoTranslate: Bool {
        get { defaults.bool(forKey: Self.autoTranslateKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.autoTranslateKey) }
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 276 tests in 46 suites passed`，零警告。

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenshotModule/AnnotationModel.swift Sources/ScreenshotModule/AnnotationSettings.swift Sources/ScreenshotModule/ScreenshotSettings.swift Tests/ScreenshotModuleTests/AnnotationModelTests.swift
git commit -m "feat(annotation): annotation state machine with undo/redo and numbering; remembered color and size"
```

---
### Task 3: 渲染 —— 屏幕绘制、导出合成、马赛克

**Files:**
- Create: `Sources/ScreenshotModule/AnnotationRenderer.swift`
- Test: `Tests/ScreenshotModuleTests/AnnotationRendererTests.swift`

**Interfaces:**
- Consumes: Task 1 的全部类型
- Produces:
  - `final class MosaicCache { func image(for rect: CGRect, block: CGFloat, make: () -> CGImage?) -> CGImage?; func removeAll() }`
  - `enum AnnotationRenderer`：
    - `static func draw(_ items: [Annotation], in context: CGContext, selectionSize: CGSize, baseImage: CGImage?, cache: MosaicCache? = nil)` —— 调用前 context 必须已是选区内坐标（左上原点、y 向下、1 单位 = 1pt）；内部裁剪到选区范围
    - `static func flatten(base: CGImage, items: [Annotation], pointSize: CGSize, onlyMosaic: Bool = false) -> CGImage?` —— 输出与 `base` 同像素尺寸；没有要合成的标注时返回 `base` 本身（`===`）；位图上下文创建失败返回 nil

坐标要点：CoreGraphics 位图的原点在左下角。`flatten` 先按原样画底图，再 `translateBy(0, 高)` + `scaleBy(宽比, -高比)` 翻成左上原点并按像素倍数放大，之后所有几何直接用 pt。往这种 y 向下的上下文里画**图片**会上下颠倒，所以马赛克小图要就地再翻一次；画**文字**则用 `NSGraphicsContext(cgContext:flipped: true)` 告诉 AppKit。测试里专门有一条断言（`bitmap.pixel(40, 50).isWhite`）用来抓"y 方向画反了"。

- [ ] **Step 1: 写失败的测试**

`Tests/ScreenshotModuleTests/AnnotationRendererTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct AnnotationRendererTests {
    struct RGBA: Equatable {
        let red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8

        var isReddish: Bool { red > 200 && green < 110 && blue < 110 }
        var isWhite: Bool { red > 250 && green > 250 && blue > 250 }
    }

    /// 把图片读成像素数组。x、y 以左上角为原点。
    private struct Bitmap {
        let width: Int
        let height: Int
        private let bytes: [UInt8]
        private let bytesPerRow: Int

        init(_ image: CGImage) throws {
            let context = try #require(CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let data = try #require(context.data)
            width = image.width
            height = image.height
            bytesPerRow = context.bytesPerRow
            bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: bytesPerRow * image.height))
        }

        func pixel(_ x: Int, _ y: Int) -> RGBA {
            let offset = y * bytesPerRow + x * 4
            return RGBA(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2], alpha: bytes[offset + 3])
        }
    }

    private func makeContext(width: Int, height: Int) throws -> CGContext {
        try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
    }

    /// 纯白底图
    private func whiteImage(width: Int, height: Int) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    /// 每 2 像素一条竖条纹、左半偏红右半偏蓝的底图：相邻像素颜色不同，方便看出马赛克是否生效
    private func stripedImage(width: Int, height: Int) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        for x in 0..<width {
            let bright: CGFloat = (x / 2) % 2 == 0 ? 1.0 : 0.2
            let color = x < width / 2
                ? CGColor(srgbRed: bright, green: 0.1, blue: 0.1, alpha: 1)
                : CGColor(srgbRed: 0.1, green: 0.1, blue: bright, alpha: 1)
            context.setFillColor(color)
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return try #require(context.makeImage())
    }

    private func rectangle(_ rect: CGRect) -> Annotation {
        Annotation(kind: .rectangle(rect), color: .red, size: .medium)
    }

    // MARK: flatten

    @Test func noAnnotationsReturnsTheBaseImageItself() throws {
        let base = try whiteImage(width: 100, height: 60)
        let output = try #require(AnnotationRenderer.flatten(base: base, items: [], pointSize: CGSize(width: 100, height: 60)))
        #expect(output === base)
    }

    @Test func rectangleStrokesTheEdgeAndLeavesTheInteriorUntouched() throws {
        let base = try whiteImage(width: 100, height: 60)
        let output = try #require(AnnotationRenderer.flatten(
            base: base, items: [rectangle(CGRect(x: 20, y: 10, width: 40, height: 30))], pointSize: CGSize(width: 100, height: 60)))
        let bitmap = try Bitmap(output)

        #expect(bitmap.width == 100)
        #expect(bitmap.height == 60)
        #expect(bitmap.pixel(20, 25).isReddish)        // 左边
        #expect(bitmap.pixel(40, 10).isReddish)        // 上边（y 向下：上边在 y = 10）
        #expect(bitmap.pixel(40, 39).isReddish)        // 下边
        #expect(bitmap.pixel(40, 25).isWhite)          // 内部
        #expect(bitmap.pixel(5, 5).isWhite)            // 外部
        #expect(bitmap.pixel(40, 50).isWhite)          // 如果 y 方向画反了，这里会是红的
    }

    @Test func retinaOutputKeepsPixelSizeAndScalesGeometry() throws {
        let base = try whiteImage(width: 200, height: 120)      // 100×60 pt 的 2× 图
        let output = try #require(AnnotationRenderer.flatten(
            base: base, items: [rectangle(CGRect(x: 20, y: 10, width: 40, height: 30))], pointSize: CGSize(width: 100, height: 60)))
        let bitmap = try Bitmap(output)

        #expect(bitmap.width == 200)
        #expect(bitmap.height == 120)
        #expect(bitmap.pixel(40, 50).isReddish)        // (20, 25) pt → (40, 50) px
        #expect(bitmap.pixel(80, 50).isWhite)
    }

    @Test func mosaicMakesBlocksUniformAndLeavesTheRestUntouched() throws {
        let base = try stripedImage(width: 120, height: 60)
        let original = try Bitmap(base)
        let mosaic = Annotation(kind: .mosaic(CGRect(x: 24, y: 12, width: 48, height: 24)), color: .red, size: .medium)   // 方块 12pt
        let output = try #require(AnnotationRenderer.flatten(base: base, items: [mosaic], pointSize: CGSize(width: 120, height: 60)))
        let bitmap = try Bitmap(output)

        // 原图里这两个点颜色不同；马赛克后它们在同一个方块里，颜色一致
        #expect(original.pixel(25, 13) != original.pixel(27, 13))
        #expect(bitmap.pixel(25, 13) == bitmap.pixel(27, 13))
        #expect(bitmap.pixel(25, 13) == bitmap.pixel(34, 22))
        // 不同方块可以不同：最左一块（偏红区）和最右一块（偏蓝区）
        #expect(bitmap.pixel(30, 18) != bitmap.pixel(66, 18))
        // 马赛克区域之外保持原样
        #expect(bitmap.pixel(10, 5) == original.pixel(10, 5))
        #expect(bitmap.pixel(100, 50) == original.pixel(100, 50))
    }

    @Test func onlyMosaicSkipsEverythingElse() throws {
        let base = try stripedImage(width: 120, height: 60)
        let original = try Bitmap(base)
        let items = [
            rectangle(CGRect(x: 80, y: 10, width: 30, height: 30)),
            Annotation(kind: .mosaic(CGRect(x: 24, y: 12, width: 48, height: 24)), color: .red, size: .medium),
        ]
        let output = try #require(AnnotationRenderer.flatten(
            base: base, items: items, pointSize: CGSize(width: 120, height: 60), onlyMosaic: true))
        let bitmap = try Bitmap(output)

        #expect(bitmap.pixel(80, 25) == original.pixel(80, 25))      // 方框没有画上去
        #expect(bitmap.pixel(25, 13) == bitmap.pixel(27, 13))        // 马赛克生效
    }

    @Test func onlyMosaicWithoutAnyMosaicReturnsTheBase() throws {
        let base = try whiteImage(width: 50, height: 50)
        let output = try #require(AnnotationRenderer.flatten(
            base: base, items: [rectangle(CGRect(x: 5, y: 5, width: 20, height: 20))],
            pointSize: CGSize(width: 50, height: 50), onlyMosaic: true))
        #expect(output === base)
    }

    @Test func everyKindRendersWithoutCrashingAndChangesPixels() throws {
        let base = try whiteImage(width: 200, height: 150)
        let size = CGSize(width: 200, height: 150)
        let kinds: [Annotation.Kind] = [
            .ellipse(CGRect(x: 10, y: 10, width: 60, height: 40)),
            .line(from: CGPoint(x: 10, y: 70), to: CGPoint(x: 90, y: 70)),
            .arrow(from: CGPoint(x: 10, y: 90), to: CGPoint(x: 90, y: 90)),
            .pen([CGPoint(x: 100, y: 10), CGPoint(x: 120, y: 30), CGPoint(x: 140, y: 10)]),
            .highlighter([CGPoint(x: 100, y: 60), CGPoint(x: 180, y: 60)]),
            .text("标注 Text", origin: CGPoint(x: 100, y: 80)),
            .number(3, center: CGPoint(x: 40, y: 125)),
        ]
        for kind in kinds {
            let output = try #require(AnnotationRenderer.flatten(
                base: base, items: [Annotation(kind: kind, color: .blue, size: .medium)], pointSize: size))
            let bitmap = try Bitmap(output)
            var changed = 0
            for y in stride(from: 0, to: 150, by: 2) {
                for x in stride(from: 0, to: 200, by: 2) where !bitmap.pixel(x, y).isWhite {
                    changed += 1
                }
            }
            #expect(changed > 0, "\(kind)")
        }
    }

    @Test func highlighterIsTranslucent() throws {
        let base = try whiteImage(width: 100, height: 60)
        let item = Annotation(kind: .highlighter([CGPoint(x: 10, y: 30), CGPoint(x: 90, y: 30)]), color: .black, size: .medium)
        let output = try #require(AnnotationRenderer.flatten(base: base, items: [item], pointSize: CGSize(width: 100, height: 60)))
        let pixel = try Bitmap(output).pixel(50, 30)
        // 40% 的黑盖在白底上 ≈ 153：明显变暗，但远没有全黑
        #expect(pixel.red > 120)
        #expect(pixel.red < 190)
    }

    // MARK: draw（屏幕绘制路径）：裁剪到选区

    @Test func drawingIsClippedToTheSelection() throws {
        let context = try makeContext(width: 200, height: 100)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        // 模拟 OverlayView：左上角原点，再平移到选区原点 (50, 20)；选区 100×60
        context.translateBy(x: 0, y: 100)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 50, y: 20)
        let pen = Annotation(kind: .pen([CGPoint(x: 10, y: 30), CGPoint(x: 190, y: 30)]), color: .red, size: .medium)

        AnnotationRenderer.draw([pen], in: context, selectionSize: CGSize(width: 100, height: 60), baseImage: nil)

        let bitmap = try Bitmap(try #require(context.makeImage()))
        #expect(bitmap.pixel(100, 50).isReddish)       // 选区内 (50, 30)
        #expect(bitmap.pixel(170, 50).isWhite)         // 选区外 (120, 30)：被裁掉
    }

    @Test func mosaicCacheReusesTheImageForTheSameRect() throws {
        let cache = MosaicCache()
        let image = try whiteImage(width: 4, height: 4)
        var builds = 0
        let rect = CGRect(x: 1, y: 2, width: 30, height: 40)
        let first = cache.image(for: rect, block: 12) { builds += 1; return image }
        let second = cache.image(for: rect, block: 12) { builds += 1; return image }
        _ = cache.image(for: rect, block: 8) { builds += 1; return image }
        #expect(first === second)
        #expect(builds == 2)
        cache.removeAll()
        _ = cache.image(for: rect, block: 12) { builds += 1; return image }
        #expect(builds == 3)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'AnnotationRenderer' in scope`

- [ ] **Step 3: 写实现**

`Sources/ScreenshotModule/AnnotationRenderer.swift`:

```swift
import AppKit
import CoreGraphics

/// 一次截图会话内的马赛克缓存：同一个马赛克标注只像素化一次。遮罩结束即随视图一起释放。
final class MosaicCache {
    private struct Key: Hashable {
        let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, block: CGFloat
    }

    private var images: [Key: CGImage] = [:]

    func image(for rect: CGRect, block: CGFloat, make: () -> CGImage?) -> CGImage? {
        let key = Key(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height, block: block)
        if let cached = images[key] { return cached }
        let created = make()
        images[key] = created
        return created
    }

    func removeAll() {
        images.removeAll()
    }
}

/// 把标注画出来：屏幕上实时绘制和导出图片用的是同一套代码。
enum AnnotationRenderer {
    /// 在 context 里画标注。调用前 context 必须已经是"选区内坐标"：
    /// 选区左上角为原点、y 向下、1 个单位 = 1pt（导出时由 flatten 按像素倍数放大）。
    /// 标注只画在选区范围内（超出部分被裁掉）。
    /// baseImage 是选区裁剪出来的原图，马赛克从它取像素。
    static func draw(
        _ items: [Annotation],
        in context: CGContext,
        selectionSize: CGSize,
        baseImage: CGImage?,
        cache: MosaicCache? = nil
    ) {
        guard !items.isEmpty else { return }
        let bounds = CGRect(origin: .zero, size: selectionSize)
        context.saveGState()
        context.clip(to: bounds)
        for item in items {
            context.saveGState()
            draw(item, in: context, bounds: bounds, baseImage: baseImage, cache: cache)
            context.restoreGState()
        }
        context.restoreGState()
    }

    /// 导出：把标注合成到选区裁剪图上，输出与 base 同样像素尺寸的新图。
    /// onlyMosaic = true 时只应用马赛克（给文字识别用：被遮住的内容不会被识别，其他标注不干扰识别）。
    /// 没有需要合成的标注时直接返回 base；位图上下文创建失败时返回 nil。
    static func flatten(base: CGImage, items: [Annotation], pointSize: CGSize, onlyMosaic: Bool = false) -> CGImage? {
        let applied = onlyMosaic ? items.filter(\.isMosaic) : items
        guard !applied.isEmpty else { return base }
        guard pointSize.width > 0, pointSize.height > 0,
              let context = CGContext(
                  data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        let pixelSize = CGSize(width: base.width, height: base.height)
        context.draw(base, in: CGRect(origin: .zero, size: pixelSize))
        // CG 的原点在左下角：翻转成左上角原点，并按像素倍数放大，之后就可以直接用选区内坐标（pt）
        context.translateBy(x: 0, y: pixelSize.height)
        context.scaleBy(x: pixelSize.width / pointSize.width, y: -pixelSize.height / pointSize.height)
        draw(applied, in: context, selectionSize: pointSize, baseImage: base)
        return context.makeImage()
    }

    // MARK: 单个标注

    private static func draw(_ item: Annotation, in context: CGContext, bounds: CGRect, baseImage: CGImage?, cache: MosaicCache?) {
        let width = item.size.strokeWidth
        context.setStrokeColor(item.color.cgColor())
        context.setFillColor(item.color.cgColor())
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch item.kind {
        case .rectangle(let rect):
            context.setLineJoin(.miter)
            context.stroke(rect)

        case .ellipse(let rect):
            context.strokeEllipse(in: rect)

        case .line(let from, let to):
            strokePath([from, to], in: context)

        case .arrow(let from, let to):
            strokePath([from, AnnotationGeometry.arrowShaftEnd(from: from, to: to, lineWidth: width)], in: context)
            let head = AnnotationGeometry.arrowHead(from: from, to: to, lineWidth: width)
            context.beginPath()
            context.addLines(between: head)
            context.closePath()
            context.fillPath()

        case .pen(let points):
            strokePath(points, in: context)

        case .highlighter(let points):
            context.setStrokeColor(item.color.cgColor(alpha: annotationHighlighterAlpha))
            context.setLineWidth(item.size.highlighterWidth)
            context.setLineCap(.butt)
            strokePath(points, in: context)

        case .text(let string, let origin):
            drawText(string, at: origin, font: .systemFont(ofSize: item.size.fontSize, weight: .medium),
                     color: item.color.cgColor(), in: context)

        case .number(let number, let center):
            let diameter = item.size.numberDiameter
            context.fillEllipse(in: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
            let font = NSFont.systemFont(ofSize: (diameter * 0.55).rounded(), weight: .bold)
            let text = "\(number)" as NSString
            let textSize = text.size(withAttributes: [.font: font])
            let textColor: CGColor = item.color.numberTextIsBlack ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1)
            drawText(text as String, at: CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2),
                     font: font, color: textColor, in: context)

        case .mosaic(let rect):
            drawMosaic(rect.intersection(bounds), block: item.size.mosaicBlock, selectionSize: bounds.size,
                       baseImage: baseImage, cache: cache, in: context)
        }
    }

    private static func strokePath(_ points: [CGPoint], in context: CGContext) {
        guard points.count >= 2 else { return }
        context.beginPath()
        context.addLines(between: points)
        context.strokePath()
    }

    /// origin 是文字左上角。context 是 y 向下的，所以告诉 AppKit 这是一个 flipped 的上下文，文字才不会倒过来。
    private static func drawText(_ string: String, at origin: CGPoint, font: NSFont, color: CGColor, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: color) ?? .red,
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        (string as NSString).draw(at: origin, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: 马赛克

    private static func drawMosaic(
        _ rect: CGRect, block: CGFloat, selectionSize: CGSize,
        baseImage: CGImage?, cache: MosaicCache?, in context: CGContext
    ) {
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return }
        let make = { pixelated(rect, block: block, selectionSize: selectionSize, baseImage: baseImage) }
        guard let image = cache?.image(for: rect, block: block, make: make) ?? make() else {
            context.setFillColor(CGColor(gray: 0.5, alpha: 1))      // 取不到原图：退而求其次，盖一块灰色
            context.fill(rect)
            return
        }
        // 往 y 向下的上下文里画图片会上下颠倒，所以就地再翻一次
        context.saveGState()
        context.clip(to: rect)
        context.interpolationQuality = .none                        // 放大时保持方块的硬边
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    /// 把 rect 对应的原图缩小成"每个方块一个像素"的小图；再放大画回去就是马赛克。
    private static func pixelated(_ rect: CGRect, block: CGFloat, selectionSize: CGSize, baseImage: CGImage?) -> CGImage? {
        guard let baseImage, selectionSize.width > 0, selectionSize.height > 0 else { return nil }
        let scaleX = CGFloat(baseImage.width) / selectionSize.width
        let scaleY = CGFloat(baseImage.height) / selectionSize.height
        let pixelRect = CGRect(
            x: (rect.minX * scaleX).rounded(), y: (rect.minY * scaleY).rounded(),
            width: (rect.width * scaleX).rounded(), height: (rect.height * scaleY).rounded()
        ).intersection(CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height))
        guard !pixelRect.isNull, pixelRect.width >= 1, pixelRect.height >= 1,
              let source = baseImage.cropping(to: pixelRect)
        else { return nil }

        let columns = max(1, Int((rect.width / block).rounded()))
        let rows = max(1, Int((rect.height / block).rounded()))
        guard let small = CGContext(
            data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        small.interpolationQuality = .medium                        // 缩小时取平均色
        small.draw(source, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        return small.makeImage()
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 286 tests in 47 suites passed`，零警告。

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenshotModule/AnnotationRenderer.swift Tests/ScreenshotModuleTests/AnnotationRendererTests.swift
git commit -m "feat(annotation): renderer shared by on-screen drawing and export, with mosaic pixelation and session cache"
```

---
### Task 4: 纯逻辑整合 —— 选区锁定、带标注的成品、取消层级、样式栏位置

**Files:**
- Create: `Sources/ScreenshotModule/OverlayCancel.swift`
- Modify（整体替换）: `Sources/ScreenshotModule/SelectionModel.swift`, `Sources/ScreenshotModule/DisplaySnapshot.swift`, `Sources/ScreenshotModule/ToolbarPlacement.swift`
- Test: `Tests/ScreenshotModuleTests/OverlayCancelTests.swift`（新增）；`Tests/ScreenshotModuleTests/SelectionModelTests.swift`, `Tests/ScreenshotModuleTests/CaptureResultTests.swift`, `Tests/ScreenshotModuleTests/ToolbarPlacementTests.swift`（整体替换：在原有用例后追加）

**Interfaces:**
- Consumes: `AnnotationRenderer.flatten`（Task 3）、`Annotation`（Task 1）
- Produces:
  - `SelectionModel.isLocked: Bool`（`public var`，默认 false）。为 true 时 `mouseDown` 直接忽略（于是后续的拖动 / 松手也无效果）、`handle(at:)` 返回 nil；`cancel()` / `reset()` 照常工作，`reset()` 会把它复位为 false
  - `CaptureResult`：新增 `ocrImage: CGImage`、`annotationsDropped: Bool`；`static func make(selection:snapshot:annotations: [Annotation] = []) -> CaptureResult?`（`image` = 裁剪图 + 全部标注；`ocrImage` = 裁剪图 + 仅马赛克；合成失败时 `image` 退回裁剪图且 `annotationsDropped = true`）
  - `enum CancelLevel { finishText, deselectTool, clearSelection, exitCapture }`；`enum OverlayCancel { static func level(isEditingText:hasTool:hasSelection:) -> CancelLevel }`
  - `ToolbarPlacement.styleBarOrigin(barSize:toolbarFrame:selection:bounds:gap: CGFloat = 6) -> CGPoint`

`make` 的新参数有默认值，所以本任务结束时 `CaptureOverlayController` 不用改也能编译。

- [ ] **Step 1: 写失败的测试**

`Tests/ScreenshotModuleTests/OverlayCancelTests.swift`:

```swift
import Testing
@testable import ScreenshotModule

@Suite struct OverlayCancelTests {
    @Test func finishingTextComesFirst() {
        #expect(OverlayCancel.level(isEditingText: true, hasTool: true, hasSelection: true) == .finishText)
    }

    @Test func thenDeselectingTheTool() {
        #expect(OverlayCancel.level(isEditingText: false, hasTool: true, hasSelection: true) == .deselectTool)
    }

    @Test func thenClearingTheSelection() {
        #expect(OverlayCancel.level(isEditingText: false, hasTool: false, hasSelection: true) == .clearSelection)
    }

    @Test func finallyExitingTheCapture() {
        #expect(OverlayCancel.level(isEditingText: false, hasTool: false, hasSelection: false) == .exitCapture)
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

    // MARK: 锁定（标注期间）

    @Test func lockedSelectionIgnoresMoveResizeAndRedraw() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 250))
        let original = model.selection
        model.isLocked = true

        // 选区内拖动：不移动
        model.mouseDown(at: CGPoint(x: 200, y: 200))
        model.mouseDragged(to: CGPoint(x: 260, y: 260))
        model.mouseUp(at: CGPoint(x: 260, y: 260))
        #expect(model.selection == original)
        #expect(!model.isAdjusting)

        // 手柄：不可用
        #expect(model.handle(at: CGPoint(x: 300, y: 250)) == nil)
        model.mouseDown(at: CGPoint(x: 300, y: 250))
        model.mouseDragged(to: CGPoint(x: 400, y: 400))
        model.mouseUp(at: CGPoint(x: 400, y: 400))
        #expect(model.selection == original)

        // 选区外拖动：不开始新选区
        model.mouseDown(at: CGPoint(x: 600, y: 600))
        model.mouseDragged(to: CGPoint(x: 700, y: 700))
        model.mouseUp(at: CGPoint(x: 700, y: 700))
        #expect(model.selection == original)
        #expect(model.hasConfirmedSelection)
    }

    @Test func unlockingRestoresNormalBehaviour() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 250))
        model.isLocked = true
        model.isLocked = false
        model.mouseDown(at: CGPoint(x: 200, y: 200))
        model.mouseDragged(to: CGPoint(x: 250, y: 220))
        model.mouseUp(at: CGPoint(x: 250, y: 220))
        #expect(model.selection == CGRect(x: 150, y: 120, width: 200, height: 150))
    }

    @Test func cancelAndResetStillWorkWhenLockedAndUnlock() {
        var model = makeSelected(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 250))
        model.isLocked = true
        #expect(model.cancel() == false)
        #expect(model.selection == nil)
        #expect(!model.isLocked)
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

    // MARK: 标注

    @Test func withoutAnnotationsBothImagesAreThePlainCrop() throws {
        let result = try #require(CaptureResult.make(
            selection: CGRect(x: 10, y: 5, width: 40, height: 20), snapshot: try makeSnapshot()
        ))
        #expect(result.image === result.ocrImage)
        #expect(!result.annotationsDropped)
    }

    @Test func annotationsAreFlattenedIntoTheImageButOnlyMosaicIntoTheOCRImage() throws {
        let selection = CGRect(x: 10, y: 5, width: 40, height: 20)
        let box = Annotation(kind: .rectangle(CGRect(x: 4, y: 4, width: 20, height: 10)), color: .red, size: .small)

        let boxed = try #require(CaptureResult.make(selection: selection, snapshot: try makeSnapshot(), annotations: [box]))
        #expect(boxed.image.width == 80)
        #expect(boxed.image.height == 40)
        #expect(boxed.image !== boxed.ocrImage)          // image 是新合成的图
        #expect(!boxed.annotationsDropped)

        let plain = try #require(CaptureResult.make(selection: selection, snapshot: try makeSnapshot()))
        #expect(boxed.ocrImage.width == plain.image.width)

        let mosaic = Annotation(kind: .mosaic(CGRect(x: 4, y: 4, width: 24, height: 12)), color: .red, size: .small)
        let hidden = try #require(CaptureResult.make(selection: selection, snapshot: try makeSnapshot(), annotations: [box, mosaic]))
        #expect(hidden.image !== hidden.ocrImage)        // 两张都是新图：一张带全部标注，一张只带马赛克
        #expect(hidden.ocrImage.width == 80)
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

    // MARK: 标注样式栏

    private let styleBar = CGSize(width: 260, height: 36)

    @Test func styleBarGoesBelowAToolbarThatIsBelowTheSelection() {
        let selection = CGRect(x: 200, y: 100, width: 500, height: 300)
        let toolbarFrame = CGRect(x: 100, y: 408, width: 600, height: 40)
        let origin = ToolbarPlacement.styleBarOrigin(barSize: styleBar, toolbarFrame: toolbarFrame, selection: selection, bounds: bounds)
        #expect(origin == CGPoint(x: 100, y: 454))       // 448 + 6
    }

    @Test func styleBarGoesAboveAToolbarThatIsAboveTheSelection() {
        let selection = CGRect(x: 200, y: 400, width: 500, height: 380)
        let toolbarFrame = CGRect(x: 100, y: 352, width: 600, height: 40)
        let origin = ToolbarPlacement.styleBarOrigin(barSize: styleBar, toolbarFrame: toolbarFrame, selection: selection, bounds: bounds)
        #expect(origin == CGPoint(x: 100, y: 310))       // 352 - 6 - 36：不盖住选区
    }

    @Test func styleBarFlipsWhenThePreferredSideDoesNotFit() {
        // 工具条在选区下方，但已经贴近屏幕底部：样式栏改到工具条上方
        let selection = CGRect(x: 200, y: 300, width: 500, height: 440)
        let toolbarFrame = CGRect(x: 100, y: 748, width: 600, height: 40)
        let origin = ToolbarPlacement.styleBarOrigin(barSize: styleBar, toolbarFrame: toolbarFrame, selection: selection, bounds: bounds)
        #expect(origin == CGPoint(x: 100, y: 706))
    }

    @Test func styleBarStaysOnScreenHorizontally() {
        let selection = CGRect(x: 900, y: 100, width: 100, height: 100)
        let toolbarFrame = CGRect(x: 900, y: 208, width: 100, height: 40)
        let origin = ToolbarPlacement.styleBarOrigin(barSize: styleBar, toolbarFrame: toolbarFrame, selection: selection, bounds: bounds)
        #expect(origin == CGPoint(x: 740, y: 254))       // 1000 - 260
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`cannot find 'OverlayCancel' in scope`、`value of type 'SelectionModel' has no member 'isLocked'` 等

- [ ] **Step 3: 写实现**

`Sources/ScreenshotModule/OverlayCancel.swift`:

```swift
import Foundation

/// Esc / 右键要做的事，按优先级从高到低。
enum CancelLevel: Equatable {
    /// 正在输入文字 → 完成文字输入
    case finishText
    /// 有工具选中 → 取消选中工具
    case deselectTool
    /// 有选区 → 清除选区（连同全部标注和重做栈），回到窗口识别状态
    case clearSelection
    /// 什么都没有 → 退出截图
    case exitCapture
}

/// 取消键的层级。纯函数。
enum OverlayCancel {
    static func level(isEditingText: Bool, hasTool: Bool, hasSelection: Bool) -> CancelLevel {
        if isEditingText { return .finishText }
        if hasTool { return .deselectTool }
        if hasSelection { return .clearSelection }
        return .exitCapture
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
    /// 选区锁定：有标注工具选中或已有标注时为 true。锁定期间选区不能移动 / 改大小，
    /// 选区外拖动也不会开始新选区，手柄不可用。cancel / reset 不受影响（并会解除锁定）。
    public var isLocked = false
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
        guard !isLocked, case .selected(let rect) = state else { return nil }
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
        guard !isLocked else { return }
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
        isLocked = false
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
    /// 复制 / 保存 / 贴图用：选区裁剪图 + 全部标注
    public let image: CGImage
    /// 文字识别 / 翻译用：选区裁剪图 + 仅马赛克（被遮住的内容不会被识别，箭头、方框等不干扰识别）
    public let ocrImage: CGImage
    /// 标注没能合成上去（位图上下文创建失败），image 退回成了不带标注的原图
    public let annotationsDropped: Bool
    /// 图片的 pt 尺寸（= 选区大小）
    public let pointSize: CGSize
    /// 选区在屏幕上的位置，AppKit 全局坐标 —— 贴图窗口直接用它当 frame
    public let screenRect: CGRect

    /// 按选区（屏内坐标）从定格画面裁出成品，并把标注（选区内坐标）合成上去。选区无效时返回 nil。
    public static func make(selection: CGRect, snapshot: DisplaySnapshot, annotations: [Annotation] = []) -> CaptureResult? {
        guard let cropped = ImageCropper.crop(snapshot.image, rect: selection, scale: snapshot.imageScale) else { return nil }
        let annotated = AnnotationRenderer.flatten(base: cropped, items: annotations, pointSize: selection.size)
        let forOCR = AnnotationRenderer.flatten(base: cropped, items: annotations, pointSize: selection.size, onlyMosaic: true)
        return CaptureResult(
            image: annotated ?? cropped,
            ocrImage: forOCR ?? cropped,
            annotationsDropped: annotated == nil,
            pointSize: selection.size,
            screenRect: ScreenGeometry.appKitRect(fromLocal: selection, screenFrame: snapshot.screen.frame)
        )
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

    /// 识别结果面板放在选区旁边，方便对照原图：右 → 左 → 下 → 上 → 选区内右下角。始终完整落在屏幕内。
    public static func sidePanelOrigin(panelSize: CGSize, selection: CGRect, bounds: CGRect, gap: CGFloat = 12) -> CGPoint {
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, bounds.minX), max(bounds.maxX - panelSize.width, bounds.minX)) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, bounds.minY), max(bounds.maxY - panelSize.height, bounds.minY)) }

        let right = selection.maxX + gap
        if right + panelSize.width <= bounds.maxX {
            return CGPoint(x: right, y: clampY(selection.minY))
        }
        let left = selection.minX - gap - panelSize.width
        if left >= bounds.minX {
            return CGPoint(x: left, y: clampY(selection.minY))
        }
        let below = selection.maxY + gap
        if below + panelSize.height <= bounds.maxY {
            return CGPoint(x: clampX(selection.minX), y: below)
        }
        let above = selection.minY - gap - panelSize.height
        if above >= bounds.minY {
            return CGPoint(x: clampX(selection.minX), y: above)
        }
        return CGPoint(
            x: clampX(min(selection.maxX, bounds.maxX) - gap - panelSize.width),
            y: clampY(min(selection.maxY, bounds.maxY) - gap - panelSize.height)
        )
    }

    /// 标注样式栏（颜色 / 粗细）：紧贴工具条、左对齐，放在工具条"背向选区"的一侧 ——
    /// 工具条在选区下方 → 样式栏在工具条下方；工具条在选区上方或选区内 → 样式栏在工具条上方。
    /// 首选的一侧放不下就换另一侧。水平方向始终不超出屏幕。
    public static func styleBarOrigin(
        barSize: CGSize, toolbarFrame: CGRect, selection: CGRect, bounds: CGRect, gap: CGFloat = 6
    ) -> CGPoint {
        let x = min(max(toolbarFrame.minX, bounds.minX), max(bounds.minX, bounds.maxX - barSize.width))
        let below = toolbarFrame.maxY + gap
        let above = toolbarFrame.minY - gap - barSize.height
        let fitsBelow = below + barSize.height <= bounds.maxY
        let fitsAbove = above >= bounds.minY
        let prefersBelow = toolbarFrame.minY >= selection.maxY
        if prefersBelow {
            return CGPoint(x: x, y: fitsBelow || !fitsAbove ? below : above)
        }
        return CGPoint(x: x, y: fitsAbove || !fitsBelow ? above : below)
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 299 tests in 48 suites passed`，零警告。

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenshotModule/OverlayCancel.swift Sources/ScreenshotModule/SelectionModel.swift Sources/ScreenshotModule/DisplaySnapshot.swift Sources/ScreenshotModule/ToolbarPlacement.swift Tests/ScreenshotModuleTests
git commit -m "feat(annotation): selection lock, annotated capture result with mosaic-only OCR image, cancel levels, style bar placement"
```

---
### Task 5: 界面 —— 工具条、样式栏、在遮罩上画标注、文字输入

**Files:**
- Create: `Sources/ScreenshotModule/AnnotationStyleBar.swift`
- Modify（整体替换）: `Sources/ScreenshotModule/CaptureAction.swift`, `Sources/ScreenshotModule/CaptureToolbar.swift`, `Sources/ScreenshotModule/OverlayView.swift`, `Sources/ScreenshotModule/CaptureOverlayController.swift`
- Test: `Tests/ScreenshotModuleTests/AnnotationUITests.swift`（新增）；`Tests/ScreenshotModuleTests/OverlayKeyMapTests.swift`（整体替换：追加 ⌘Z / ⇧⌘Z）

**Interfaces:**
- Consumes: `AnnotationModel`、`AnnotationSettings`、`ScreenshotSettings.annotation`（Task 2）；`AnnotationRenderer`、`MosaicCache`（Task 3）；`SelectionModel.isLocked`、`CaptureResult.make(selection:snapshot:annotations:)`、`OverlayCancel`、`ToolbarPlacement.styleBarOrigin`（Task 4）；`ImageCropper.crop`（第一期）
- Produces:
  - `OverlayCommand` 增加 `.undo`、`.redo`；`OverlayKeyMap`：`⌘Z` → `.undo`，`⇧⌘Z` → `.redo`
  - `CaptureToolbar`：`onCommand`、`onToolToggle: ((AnnotationTool) -> Void)?`、`func update(selectedTool:canUndo:canRedo:)`
  - `AnnotationStyleBar`：`onColor`、`onSize`、`func update(color:size:showsColors:)`
  - `OverlayView.init(frame:windows:snapshotImage:imageScale:annotationSettings:)`；`annotation: AnnotationModel`（只读）；`annotations: [Annotation]`；`handleCancel() -> Bool`（取代第一期的 `cancelSelection()`，返回 true = 这块屏上没有可取消的东西）；`resetSelection()`；`undo()`；`redo()`；`commitPendingText()`
  - `OverlayPanel`：文字输入框是第一响应者时，按键正常下发给它（Esc 例外，且输入法组字时 Esc 归输入法）；`⌘X/C/V/A/Z`、`⇧⌘Z` 转发给输入框

行为要点（对应设计文档 §2）：

- 鼠标事件分流：有工具选中且点在选区内 → `AnnotationModel`；选区锁定（有工具或有标注）时其余点击一律忽略，双击也不触发复制；未锁定时与第一期完全相同。
- 文字工具：点一下在该处放一个透明背景的 `NSTextView`（不自动换行、回车换行、支持输入法），点别处 / `Esc` / 切换工具 / 执行复制等操作时落成标注；空内容不产生标注；正在输入时点「撤销」= 放弃这次输入。
- 取消键三级由 `OverlayCancel.level` 决定；清除选区时标注、重做栈、马赛克缓存一并清掉。
- 样式栏只在有工具选中时显示；选马赛克时只显示粗细。颜色 / 粗细一改就写进 `AnnotationSettings`。
- 识别文字用 `result.ocrImage`；第一期"识别 / 翻译时遮罩不关闭"的全部逻辑保持不变。

- [ ] **Step 1: 写失败的测试**

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

    @Test func commandZUndoesAndShiftCommandZRedoes() {
        #expect(OverlayKeyMap.command(keyCode: 6, characters: "z", modifiers: [.command]) == .undo)
        #expect(OverlayKeyMap.command(keyCode: 6, characters: "z", modifiers: [.command, .shift]) == .redo)
        #expect(OverlayKeyMap.command(keyCode: 6, characters: "Z", modifiers: [.command, .shift, .capsLock]) == .redo)
        #expect(OverlayKeyMap.command(keyCode: 6, characters: "z", modifiers: []) == nil)
        #expect(OverlayKeyMap.command(keyCode: 6, characters: "z", modifiers: [.command, .option]) == nil)
    }
}
```

`Tests/ScreenshotModuleTests/AnnotationUITests.swift`:

```swift
import AppKit
import Foundation
import Testing
@testable import ScreenshotModule

/// 界面部件的冒烟测试：能创建、按钮齐全、点击能把指令送出来。真正的手感靠手动验收。
@MainActor
@Suite struct AnnotationUITests {
    private func buttons(in view: NSView) -> [NSButton] {
        view.subviews.flatMap { subview -> [NSButton] in
            (subview as? NSButton).map { [$0] } ?? buttons(in: subview)
        }
    }

    private func makeDefaults() -> UserDefaults {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func whiteImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        return try #require(context.makeImage())
    }

    @Test func toolbarHasNineToolsUndoRedoAndFiveActions() {
        let toolbar = CaptureToolbar()
        let all = buttons(in: toolbar)
        #expect(all.count == 16)
        let hints = all.compactMap(\.toolTip)
        for tool in AnnotationTool.allCases {
            #expect(hints.contains(tool.displayName), "\(tool.displayName)")
        }
        #expect(hints.contains("撤销  ⌘Z"))
        #expect(hints.contains("重做  ⇧⌘Z"))
        #expect(hints.contains("复制到剪切板  ↩"))
        #expect(toolbar.frame.width > 300)
        #expect(toolbar.frame.height > 20)
    }

    @Test func toolbarSendsToolTogglesAndCommands() throws {
        let toolbar = CaptureToolbar()
        var toggled: [AnnotationTool] = []
        var commands: [OverlayCommand] = []
        toolbar.onToolToggle = { toggled.append($0) }
        toolbar.onCommand = { commands.append($0) }
        toolbar.update(selectedTool: nil, canUndo: true, canRedo: true)
        let all = buttons(in: toolbar)

        try #require(all.first { $0.toolTip == "箭头" }).performClick(nil)
        try #require(all.first { $0.toolTip == "马赛克" }).performClick(nil)
        try #require(all.first { $0.toolTip == "撤销  ⌘Z" }).performClick(nil)
        try #require(all.first { $0.toolTip == "重做  ⇧⌘Z" }).performClick(nil)
        try #require(all.first { $0.toolTip == "保存为 PNG 文件  ⌘S" }).performClick(nil)

        #expect(toggled == [.arrow, .mosaic])
        #expect(commands == [.undo, .redo, .perform(.save)])
    }

    @Test func toolbarReflectsModelState() throws {
        let toolbar = CaptureToolbar()
        let all = buttons(in: toolbar)
        let undo = try #require(all.first { $0.toolTip == "撤销  ⌘Z" })
        let pen = try #require(all.first { $0.toolTip == "画笔" })
        #expect(!undo.isEnabled)
        #expect(pen.state == .off)

        toolbar.update(selectedTool: .pen, canUndo: true, canRedo: false)

        #expect(undo.isEnabled)
        #expect(pen.state == .on)
        #expect(all.filter { $0.state == .on && AnnotationTool.allCases.map(\.displayName).contains($0.toolTip ?? "") }.count == 1)
    }

    @Test func styleBarHidesColorsForMosaicAndReportsChoices() throws {
        let bar = AnnotationStyleBar()
        bar.update(color: .red, size: .medium, showsColors: true)
        let fullWidth = bar.frame.width
        var colors: [AnnotationColor] = []
        var sizes: [AnnotationSize] = []
        bar.onColor = { colors.append($0) }
        bar.onSize = { sizes.append($0) }
        let all = buttons(in: bar)
        #expect(all.count == 9)

        try #require(all.first { $0.toolTip == "蓝" }).performClick(nil)
        try #require(all.first { $0.title == "粗" }).performClick(nil)
        #expect(colors == [.blue])
        #expect(sizes == [.large])

        bar.update(color: .red, size: .medium, showsColors: false)
        #expect(bar.frame.width < fullWidth)
    }

    @Test func overlayViewStartsWithRememberedStyleAndNothingToCancel() throws {
        let defaults = makeDefaults()
        AnnotationSettings(defaults: defaults).color = .green
        AnnotationSettings(defaults: defaults).size = .large
        let view = OverlayView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 300), windows: [],
            snapshotImage: try whiteImage(), imageScale: 0.1,
            annotationSettings: AnnotationSettings(defaults: defaults)
        )

        #expect(view.annotation.color == .green)
        #expect(view.annotation.size == .large)
        #expect(view.annotations.isEmpty)
        #expect(view.handleCancel())          // 没有选区、没有工具：没东西可取消 → 由控制器退出截图
        view.undo()                           // 空状态下撤销 / 重做 / 提交文字都不应崩溃
        view.redo()
        view.commitPendingText()
        view.resetSelection()
        #expect(!view.model.isLocked)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`type 'OverlayCommand' has no member 'undo'`、`cannot find 'AnnotationStyleBar' in scope` 等

- [ ] **Step 3: 指令与键盘映射**

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
    /// 撤销 / 重做最后一个标注
    case undo
    case redo
}

/// 键盘 → 指令。纯函数。
enum OverlayKeyMap {
    static func command(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) -> OverlayCommand? {
        let relevant = modifiers.intersection([.command, .option, .control, .shift])
        if keyCode == 53 { return .cancel }                                   // Esc
        if relevant.isEmpty, keyCode == 36 || keyCode == 76 {                 // 回车 / 小键盘回车
            return .perform(.copy)
        }
        guard let key = characters?.lowercased() else { return nil }
        if relevant == [.command, .shift], key == "z" { return .redo }       // ⇧⌘Z
        guard relevant == .command else { return nil }
        switch key {
        case "z": return .undo
        case "c": return .perform(.copy)
        case "s": return .perform(.save)
        case "r": return .perform(.recognize)
        case "t": return .perform(.pin)
        default: return nil
        }
    }
}
```

- [ ] **Step 4: 工具条与样式栏**

`Sources/ScreenshotModule/CaptureToolbar.swift`:

```swift
import AppKit

/// 选区旁边的工具条：九种标注工具 | 撤销 重做 | 贴图 识别文字 保存 复制 取消。
final class CaptureToolbar: NSVisualEffectView {
    var onCommand: ((OverlayCommand) -> Void)?
    /// 点了某个标注工具（选中 / 再点一次取消，由 AnnotationModel 决定）
    var onToolToggle: ((AnnotationTool) -> Void)?

    private let tools = AnnotationTool.allCases
    private let actions: [(title: String, symbol: String, hint: String, command: OverlayCommand)] = [
        ("贴图", "pin", "贴在屏幕上  ⌘T", .perform(.pin)),
        ("识别文字", "text.viewfinder", "识别图中文字  ⌘R", .perform(.recognize)),
        ("保存", "square.and.arrow.down", "保存为 PNG 文件  ⌘S", .perform(.save)),
        ("复制", "doc.on.doc", "复制到剪切板  ↩", .perform(.copy)),
        ("", "xmark", "取消  Esc", .cancel),
    ]
    private var toolButtons: [NSButton] = []
    private var undoButton = NSButton()
    private var redoButton = NSButton()

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        state = .active
        blendingMode = .withinWindow
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        toolButtons = tools.enumerated().map { index, tool in
            let button = Self.iconButton(symbol: tool.symbolName, hint: tool.displayName, target: self, action: #selector(toolClicked(_:)))
            button.setButtonType(.pushOnPushOff)
            button.tag = index
            return button
        }
        undoButton = Self.iconButton(symbol: "arrow.uturn.backward", hint: "撤销  ⌘Z", target: self, action: #selector(undoClicked))
        redoButton = Self.iconButton(symbol: "arrow.uturn.forward", hint: "重做  ⇧⌘Z", target: self, action: #selector(redoClicked))
        let actionButtons = actions.enumerated().map { index, item -> NSButton in
            let image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.hint) ?? NSImage()
            let button = NSButton(title: item.title, image: image, target: self, action: #selector(actionClicked(_:)))
            button.tag = index
            button.bezelStyle = .accessoryBarAction
            button.imagePosition = item.title.isEmpty ? .imageOnly : .imageLeading
            button.toolTip = item.hint
            return button
        }

        var views: [NSView] = toolButtons
        views.append(Self.separator())
        views.append(contentsOf: [undoButton, redoButton])
        views.append(Self.separator())
        views.append(contentsOf: actionButtons)

        let stack = NSStackView(views: views)
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
        setFrameSize(stack.fittingSize)
        update(selectedTool: nil, canUndo: false, canRedo: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 按 AnnotationModel 的状态刷新：哪个工具高亮，撤销 / 重做是否可用。
    func update(selectedTool: AnnotationTool?, canUndo: Bool, canRedo: Bool) {
        for (button, tool) in zip(toolButtons, tools) {
            let selected = tool == selectedTool
            button.state = selected ? .on : .off
            button.contentTintColor = selected ? .controlAccentColor : nil
        }
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
    }

    private static func iconButton(symbol: String, hint: String, target: AnyObject, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: hint) ?? NSImage()
        let button = NSButton(image: image, target: target, action: action)
        button.bezelStyle = .accessoryBarAction
        button.imagePosition = .imageOnly
        button.toolTip = hint
        return button
    }

    private static func separator() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 18),
        ])
        return line
    }

    @objc private func toolClicked(_ sender: NSButton) {
        guard tools.indices.contains(sender.tag) else { return }
        onToolToggle?(tools[sender.tag])
    }

    @objc private func undoClicked() {
        onCommand?(.undo)
    }

    @objc private func redoClicked() {
        onCommand?(.redo)
    }

    @objc private func actionClicked(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        onCommand?(actions[sender.tag].command)
    }
}
```

`Sources/ScreenshotModule/AnnotationStyleBar.swift`:

```swift
import AppKit

/// 选中标注工具后出现在工具条旁边的样式栏：6 种颜色 + 3 档粗细。
final class AnnotationStyleBar: NSVisualEffectView {
    var onColor: ((AnnotationColor) -> Void)?
    var onSize: ((AnnotationSize) -> Void)?

    private let colors = AnnotationColor.allCases
    private let sizes = AnnotationSize.allCases
    private var colorButtons: [NSButton] = []
    private var sizeButtons: [NSButton] = []
    private let colorStack = NSStackView()
    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        state = .active
        blendingMode = .withinWindow
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        colorButtons = colors.enumerated().map { index, color in
            let button = NSButton(image: Self.swatch(color, selected: false), target: self, action: #selector(colorClicked(_:)))
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.tag = index
            button.toolTip = color.displayName
            return button
        }
        sizeButtons = sizes.enumerated().map { index, size in
            let button = NSButton(title: size.displayName, target: self, action: #selector(sizeClicked(_:)))
            button.bezelStyle = .accessoryBarAction
            button.setButtonType(.pushOnPushOff)
            button.tag = index
            return button
        }

        colorStack.orientation = .horizontal
        colorStack.spacing = 6
        colorButtons.forEach(colorStack.addArrangedSubview)
        let sizeStack = NSStackView(views: sizeButtons)
        sizeStack.orientation = .horizontal
        sizeStack.spacing = 4

        stack.orientation = .horizontal
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        stack.addArrangedSubview(colorStack)
        stack.addArrangedSubview(sizeStack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        update(color: .red, size: .medium, showsColors: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// showsColors = false：马赛克没有颜色可选，只显示粗细（= 方块大小）。
    func update(color: AnnotationColor, size: AnnotationSize, showsColors: Bool) {
        for (button, candidate) in zip(colorButtons, colors) {
            button.image = Self.swatch(candidate, selected: candidate == color)
        }
        for (button, candidate) in zip(sizeButtons, sizes) {
            button.state = candidate == size ? .on : .off
        }
        colorStack.isHidden = !showsColors
        setFrameSize(stack.fittingSize)
    }

    /// 颜色圆点；选中的外面多一圈白环。
    private static func swatch(_ color: AnnotationColor, selected: Bool) -> NSImage {
        NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
            let dot = NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4))
            (NSColor(cgColor: color.cgColor()) ?? .red).setFill()
            dot.fill()
            NSColor.white.withAlphaComponent(0.5).setStroke()      // 黑色圆点在深色底上也看得见
            dot.lineWidth = 0.5
            dot.stroke()
            if selected {
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1.25, dy: 1.25))
                NSColor.white.setStroke()
                ring.lineWidth = 1.5
                ring.stroke()
            }
            return true
        }
    }

    @objc private func colorClicked(_ sender: NSButton) {
        guard colors.indices.contains(sender.tag) else { return }
        onColor?(colors[sender.tag])
    }

    @objc private func sizeClicked(_ sender: NSButton) {
        guard sizes.indices.contains(sender.tag) else { return }
        onSize?(sizes[sender.tag])
    }
}
```

- [ ] **Step 5: 遮罩视图**

`Sources/ScreenshotModule/OverlayView.swift`:

```swift
import AppKit

@MainActor
protocol OverlayViewDelegate: AnyObject {
    /// 用户开始在这块屏上操作（其他屏的选区要清掉）
    func overlayViewDidBeginInteraction(_ view: OverlayView)
    func overlayView(_ view: OverlayView, didRequest command: OverlayCommand)
}

/// 盖在定格画面上面的那一层：画暗层、高亮 / 选区、手柄、尺寸标签和标注，
/// 并把鼠标事件交给 SelectionModel（调整选区）或 AnnotationModel（画标注）。
/// isFlipped = true，所以视图坐标就是"屏内坐标"（左上角原点）。
final class OverlayView: NSView {
    weak var delegate: OverlayViewDelegate?
    private(set) var model: SelectionModel
    private(set) var annotation: AnnotationModel

    private let toolbar = CaptureToolbar()
    private let styleBar = AnnotationStyleBar()
    private let snapshotImage: CGImage
    private let imageScale: CGFloat
    private let annotationSettings: AnnotationSettings
    /// 只在这次截图会话内有效，随视图一起释放
    private let mosaicCache = MosaicCache()
    /// 选区裁剪出来的原图（马赛克从它取像素）；选区变了就重新裁
    private var baseCrop: (selection: CGRect, image: CGImage)?
    /// 文字工具的输入框（正在输入时才有）
    private var textEditor: NSTextView?
    /// 这次鼠标拖动是在画标注（而不是在调整选区）
    private var isAnnotating = false

    private static let handleSide: CGFloat = 8
    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    init(frame: NSRect, windows: [CGRect], snapshotImage: CGImage, imageScale: CGFloat, annotationSettings: AnnotationSettings) {
        model = SelectionModel(bounds: CGRect(origin: .zero, size: frame.size), windows: windows)
        annotation = AnnotationModel(color: annotationSettings.color, size: annotationSettings.size)
        self.snapshotImage = snapshotImage
        self.imageScale = imageScale
        self.annotationSettings = annotationSettings
        super.init(frame: frame)

        toolbar.isHidden = true
        toolbar.onCommand = { [weak self] command in
            guard let self else { return }
            self.delegate?.overlayView(self, didRequest: command)
        }
        toolbar.onToolToggle = { [weak self] tool in
            self?.toggleTool(tool)
        }
        styleBar.isHidden = true
        styleBar.onColor = { [weak self] color in
            self?.setColor(color)
        }
        styleBar.onSize = { [weak self] size in
            self?.setSize(size)
        }
        addSubview(toolbar)
        addSubview(styleBar)
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

    // MARK: 给控制器用

    /// 已完成的标注（选区内坐标），导出时合成到图上。
    var annotations: [Annotation] { annotation.items }

    /// Esc / 右键。按层级处理一级；返回 true 表示这块屏上已经没有任何东西可取消（控制器据此决定是否退出截图）。
    func handleCancel() -> Bool {
        let level = OverlayCancel.level(
            isEditingText: textEditor != nil,
            hasTool: annotation.tool != nil,
            hasSelection: model.selection != nil || model.isAdjusting
        )
        switch level {
        case .finishText:
            commitPendingText()
            return false
        case .deselectTool:
            annotation.deselectTool()
            refresh()
            return false
        case .clearSelection:
            clearEverything()
            return false
        case .exitCapture:
            return true
        }
    }

    /// 另一块屏开始操作时：这块屏的选区和标注全部清掉。
    func resetSelection() {
        clearEverything()
    }

    func undo() {
        if textEditor != nil {
            discardTextEditor()              // 正在输入的文字还没变成标注：撤销 = 放弃这次输入
        } else {
            annotation.undo()
        }
        refresh()
    }

    func redo() {
        commitPendingText()
        annotation.redo()
        refresh()
    }

    /// 执行复制 / 保存等操作之前调用：把还在输入框里的文字落成标注。
    func commitPendingText() {
        guard let editor = textEditor else { return }
        let text = editor.string
        let frame = editor.frame
        discardTextEditor()
        if let selection = model.selection {
            annotation.placeText(text, at: CGPoint(x: frame.minX - selection.minX, y: frame.minY - selection.minY))
        }
        refresh()
    }

    // MARK: 标注工具与样式

    private func toggleTool(_ tool: AnnotationTool) {
        commitPendingText()
        annotation.toggleTool(tool)
        refresh()
    }

    private func setColor(_ color: AnnotationColor) {
        annotation.color = color
        annotationSettings.color = color              // 记住，下次截图沿用
        applyStyleToTextEditor()
        refresh()
    }

    private func setSize(_ size: AnnotationSize) {
        annotation.size = size
        annotationSettings.size = size
        applyStyleToTextEditor()
        refresh()
    }

    private func clearEverything() {
        discardTextEditor()
        isAnnotating = false
        model.reset()
        annotation.reset()
        mosaicCache.removeAll()
        baseCrop = nil
        refresh()
    }

    // MARK: 文字输入框

    private var textFont: NSFont {
        .systemFont(ofSize: annotation.size.fontSize, weight: .medium)
    }

    private func beginTextEditing(at point: CGPoint, in selection: CGRect) {
        let font = textFont
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let maxWidth = max(selection.maxX - point.x, 40)
        let maxHeight = max(selection.maxY - point.y, lineHeight)
        let editor = NSTextView(frame: CGRect(x: point.x, y: point.y, width: min(maxWidth, 120), height: lineHeight))
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0       // 让输入框里文字的位置和最终画出来的位置一致
        // 不自动换行（回车才换行），和导出时的画法一致；超出选区的部分同样会被裁掉
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.minSize = NSSize(width: min(maxWidth, 120), height: lineHeight)
        editor.maxSize = NSSize(width: maxWidth, height: maxHeight)
        editor.wantsLayer = true
        editor.layer?.borderWidth = 1
        editor.layer?.borderColor = NSColor.controlAccentColor.cgColor
        editor.layer?.cornerRadius = 2
        addSubview(editor, positioned: .below, relativeTo: toolbar)
        textEditor = editor
        applyStyleToTextEditor()
        window?.makeFirstResponder(editor)
    }

    private func applyStyleToTextEditor() {
        guard let editor = textEditor else { return }
        let color = NSColor(cgColor: annotation.color.cgColor()) ?? .red
        editor.font = textFont
        editor.textColor = color
        editor.insertionPointColor = color
        editor.typingAttributes = [.font: textFont, .foregroundColor: color]
    }

    private func discardTextEditor() {
        guard let editor = textEditor else { return }
        textEditor = nil
        editor.removeFromSuperview()
        window?.makeFirstResponder(self)
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
        if let selection = model.selection, model.hasConfirmedSelection {
            drawAnnotations(in: selection)
        }

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: highlight.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = model.selection == nil ? 2 : 1
        border.stroke()

        guard let selection = model.selection else { return }
        if model.hasConfirmedSelection, !model.isLocked {       // 锁定期间不显示手柄
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

    private func drawAnnotations(in selection: CGRect) {
        let inProgress = annotation.inProgress.map { [$0] } ?? []
        guard !annotation.items.isEmpty || !inProgress.isEmpty,
              let context = NSGraphicsContext.current?.cgContext
        else { return }
        let base = croppedBase(for: selection)
        context.saveGState()
        context.translateBy(x: selection.minX, y: selection.minY)      // 之后就是"选区内坐标"
        AnnotationRenderer.draw(annotation.items, in: context, selectionSize: selection.size, baseImage: base, cache: mosaicCache)
        AnnotationRenderer.draw(inProgress, in: context, selectionSize: selection.size, baseImage: base)   // 拖动中的不缓存
        context.restoreGState()
    }

    private func croppedBase(for selection: CGRect) -> CGImage? {
        if let baseCrop, baseCrop.selection == selection { return baseCrop.image }
        mosaicCache.removeAll()
        guard let image = ImageCropper.crop(snapshotImage, rect: selection, scale: imageScale) else { return nil }
        baseCrop = (selection, image)
        return image
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
        model.isLocked = annotation.locksSelection
        if model.hasConfirmedSelection, !model.isAdjusting, let selection = model.selection {
            toolbar.update(selectedTool: annotation.tool, canUndo: annotation.canUndo || textEditor != nil, canRedo: annotation.canRedo)
            toolbar.setFrameOrigin(ToolbarPlacement.toolbarOrigin(
                toolbarSize: toolbar.frame.size, selection: selection, bounds: bounds
            ))
            toolbar.isHidden = false
            if let tool = annotation.tool {
                styleBar.update(color: annotation.color, size: annotation.size, showsColors: tool.usesColor)
                styleBar.setFrameOrigin(ToolbarPlacement.styleBarOrigin(
                    barSize: styleBar.frame.size, toolbarFrame: toolbar.frame, selection: selection, bounds: bounds
                ))
                styleBar.isHidden = false
            } else {
                styleBar.isHidden = true
            }
        } else {
            toolbar.isHidden = true
            styleBar.isHidden = true
        }
        needsDisplay = true
    }

    // MARK: 鼠标

    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func local(_ point: CGPoint, in selection: CGRect) -> CGPoint {
        CGPoint(x: point.x - selection.minX, y: point.y - selection.minY)
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

        if textEditor != nil {
            commitPendingText()                 // 点别处 = 完成文字输入（这一下不再画新的东西）
            return
        }
        if annotation.tool != nil, model.hasConfirmedSelection, let selection = model.selection {
            guard selection.contains(point) else { return }     // 选区锁定：选区外的点击不做任何事
            let shift = event.modifierFlags.contains(.shift)
            switch annotation.mouseDown(at: local(point, in: selection), in: selection.size, shift: shift) {
            case .beganDrag:
                isAnnotating = true
            case .beginText:
                beginTextEditing(at: point, in: selection)
            case .placedNumber, .ignored:
                break
            }
            refresh()
            return
        }
        if annotation.locksSelection { return }                 // 没选工具但已有标注：选区同样不能动，双击也不触发复制

        if event.clickCount == 2, model.hasConfirmedSelection, model.selection?.contains(point) == true {
            delegate?.overlayView(self, didRequest: .perform(.copy))      // 双击选区 = 复制
            return
        }
        model.mouseDown(at: point)
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = location(of: event)
        if isAnnotating, let selection = model.selection {
            annotation.mouseDragged(to: local(point, in: selection), shift: event.modifierFlags.contains(.shift))
            needsDisplay = true
            return
        }
        guard !annotation.locksSelection else { return }
        model.mouseDragged(to: point)
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        let point = location(of: event)
        if isAnnotating {
            isAnnotating = false
            if let selection = model.selection {
                annotation.mouseUp(at: local(point, in: selection), shift: event.modifierFlags.contains(.shift))
            }
            refresh()
            return
        }
        guard !annotation.locksSelection else { return }
        model.mouseUp(at: point)
        updateCursor(at: point)
        refresh()
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.overlayView(self, didRequest: .cancel)
    }

    private func updateCursor(at point: CGPoint) {
        if !toolbar.isHidden, toolbar.frame.contains(point) || (!styleBar.isHidden && styleBar.frame.contains(point)) {
            NSCursor.arrow.set()                   // 工具条 / 样式栏上用普通箭头
            return
        }
        let insideSelection = model.hasConfirmedSelection && model.selection?.contains(point) == true
        if annotation.locksSelection {
            if insideSelection, let tool = annotation.tool {
                (tool == .text ? NSCursor.iBeam : NSCursor.crosshair).set()
            } else {
                NSCursor.arrow.set()
            }
            return
        }
        if let handle = model.handle(at: point) {
            switch handle {
            case .left, .right: NSCursor.resizeLeftRight.set()
            case .top, .bottom: NSCursor.resizeUpDown.set()
            case .topLeft, .topRight, .bottomLeft, .bottomRight: NSCursor.crosshair.set()
            }
        } else if insideSelection {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }
}
```

- [ ] **Step 6: 遮罩面板与会话控制器**

`Sources/ScreenshotModule/CaptureOverlayController.swift`:

```swift
import AppKit
import Core

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

    /// 文字标注的输入框正在编辑时，它是第一响应者
    private var editingTextView: NSTextView? {
        firstResponder as? NSTextView
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if let editor = editingTextView {
                // 正在输入文字：按键交给输入框（含中文输入法）。只有 Esc 例外 —— 而且输入法正在组字时 Esc 也归输入法
                if event.keyCode == 53, !editor.hasMarkedText() {
                    _ = keyHandler?(event)
                    return
                }
                super.sendEvent(event)
                return
            }
            _ = keyHandler?(event)
            return                       // 截图期间其余按键到此为止（也避免系统"咚"一声）
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let editor = editingTextView {
            forwardEditingShortcut(event, to: editor)
            return true
        }
        _ = keyHandler?(event)
        return true                      // ⌘ 组合键同样不再往下传
    }

    /// MyKit 没有主菜单，输入框里的 ⌘X / ⌘C / ⌘V / ⌘A / ⌘Z / ⇧⌘Z 要自己转发。
    private func forwardEditingShortcut(_ event: NSEvent, to editor: NSTextView) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return }
        if modifiers == [.command, .shift], key == "z" {
            editor.undoManager?.redo()
            return
        }
        guard modifiers == .command else { return }
        switch key {
        case "x": editor.cut(nil)
        case "c": editor.copy(nil)
        case "v": editor.pasteAsPlainText(nil)
        case "a": editor.selectAll(nil)
        case "z": editor.undoManager?.undo()
        default: break
        }
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

    /// 识别文字时遮罩不关闭：结果面板浮在遮罩上面、选区旁边，方便对照原图。
    private var ocrPanel: FloatingPanel?
    private let ocrModel: OCRResultModel
    private static let ocrPanelSize = NSSize(width: 400, height: 440)      // 留出下半部分显示译文
    /// 系统正在（或即将）显示"下载翻译语言包"的提示：遮罩临时降到普通窗口层级，提示才不会被挡住
    private var isYieldingToSystemPrompt = false

    /// cgWindows：截图那一刻屏幕上的窗口边框（CG 全局坐标，前 → 后）
    init(snapshots: [DisplaySnapshot], cgWindows: [CGRect], settings: ScreenshotSettings = ScreenshotSettings()) {
        ocrModel = OCRResultModel.live(settings: settings)
        entries = snapshots.map { snapshot in
            let panel = OverlayPanel(screenFrame: snapshot.screen.frame)
            let localBounds = snapshot.localBounds

            let imageView = NSImageView(frame: localBounds)
            imageView.image = NSImage(cgImage: snapshot.image, size: localBounds.size)
            imageView.imageScaling = .scaleAxesIndependently
            imageView.imageFrameStyle = .none
            imageView.autoresizingMask = [.width, .height]

            let windows = WindowLocator.localRects(cgWindows: cgWindows, displayBounds: snapshot.screen.cgBounds)
            let overlay = OverlayView(
                frame: localBounds, windows: windows,
                snapshotImage: snapshot.image, imageScale: snapshot.imageScale,
                annotationSettings: settings.annotation
            )
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
        dismissOCRPanel()
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
        dismissOCRPanel()                      // 点一下定格画面 = 收起识别结果，继续截图
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
            // 每块屏按层级处理一级（完成文字 → 取消工具 → 清选区和标注）；哪块屏都没东西可取消 → 退出截图
            var cancelledSomething = false
            for entry in entries where !entry.view.handleCancel() {
                cancelledSomething = true
            }
            if !cancelledSomething { end() }

        case .undo:
            entries.first(where: { $0.view.model.hasConfirmedSelection })?.view.undo()

        case .redo:
            entries.first(where: { $0.view.model.hasConfirmedSelection })?.view.redo()

        case .perform(let action):
            guard let entry = entries.first(where: { $0.view.model.hasConfirmedSelection }),
                  let selection = entry.view.model.selection
            else { return }                     // 还没有选区：按键无效果
            entry.view.commitPendingText()      // 还在输入框里的文字先落成标注
            guard let result = CaptureResult.make(
                selection: selection, snapshot: entry.snapshot, annotations: entry.view.annotations
            ) else { return }
            if action == .recognize {
                showRecognition(of: result, selection: selection, in: entry)   // 遮罩保持打开
                return
            }
            end()
            onFinish?(action, result)
        }
    }

    // MARK: 识别文字（遮罩不关闭）

    private func showRecognition(of result: CaptureResult, selection: CGRect, in entry: Entry) {
        dismissOCRPanel()
        let size = Self.ocrPanelSize
        let origin = ToolbarPlacement.sidePanelOrigin(panelSize: size, selection: selection, bounds: entry.snapshot.localBounds)
        let frame = ScreenGeometry.appKitRect(
            fromLocal: CGRect(origin: origin, size: size),
            screenFrame: entry.snapshot.screen.frame
        )

        let panel = FloatingPanel(size: size)
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)   // 盖在遮罩上面
        // 系统的下载提示会抢走键盘焦点；面板不能因此关闭（否则翻译到一半就没了）。
        // 只有点击定格画面 / 工具条时才收起，见 overlayViewDidBeginInteraction。
        panel.closesOnResignKey = false
        panel.keyHandler = { [weak self, weak panel] event in
            // Esc = 结束整个截图；输入法正在组字时 Esc 交给输入法
            guard event.keyCode == 53, panel?.isComposingText != true else { return false }
            self?.end()
            return true
        }
        // 面板失去焦点（用户点了定格画面）时会自己关闭
        panel.onClose = { [weak self, weak panel] in
            if self?.ocrPanel === panel { self?.ocrPanel = nil }
        }
        ocrPanel = panel
        panel.present(
            OCRResultView(
                model: ocrModel,
                closeTitle: "完成",
                onClose: { [weak self] in self?.end() },
                onLanguageDownloadActive: { [weak self] active in self?.yieldToSystemPrompt(active) }
            ),
            at: frame
        )
        Task { [ocrModel] in
            await ocrModel.run(on: result.ocrImage)      // 原图 + 仅马赛克：被遮住的不识别，箭头等不干扰
        }
    }

    /// 截图画面始终不关闭。需要下载语言包时只是临时让出窗口层级：画面还在，菜单栏会露出来；
    /// 翻译结束（或面板收起、截图结束）后恢复。
    private func yieldToSystemPrompt(_ yielding: Bool) {
        guard yielding != isYieldingToSystemPrompt else { return }
        isYieldingToSystemPrompt = yielding
        let shielding = Int(CGShieldingWindowLevel())
        for entry in entries {
            entry.panel.level = yielding ? .normal : NSWindow.Level(rawValue: shielding)
        }
        ocrPanel?.level = yielding ? .normal : NSWindow.Level(rawValue: shielding + 1)
        if yielding {
            ocrPanel?.orderFront(nil)      // 同为普通层级时，保证结果面板仍在定格画面上面
        }
    }

    private func dismissOCRPanel() {
        yieldToSystemPrompt(false)
        guard let panel = ocrPanel else { return }
        ocrPanel = nil
        panel.onClose = nil
        panel.close()
    }
}
```

- [ ] **Step 7: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 305 tests in 49 suites passed`，零警告。

- [ ] **Step 8: Commit**

```bash
git add Sources/ScreenshotModule/CaptureAction.swift Sources/ScreenshotModule/CaptureToolbar.swift Sources/ScreenshotModule/AnnotationStyleBar.swift Sources/ScreenshotModule/OverlayView.swift Sources/ScreenshotModule/CaptureOverlayController.swift Tests/ScreenshotModuleTests/OverlayKeyMapTests.swift Tests/ScreenshotModuleTests/AnnotationUITests.swift
git commit -m "feat(annotation): annotation tools on the capture overlay - toolbar, style bar, drawing, text input, undo/redo"
```

---
### Task 6: 合成失败提示、使用说明、安装与验收

**Files:**
- Modify（整体替换）: `Sources/ScreenshotModule/ScreenshotActions.swift`, `Sources/ScreenshotModule/ScreenshotModule.swift`, `README.md`
- Test: `Tests/ScreenshotModuleTests/ScreenshotActionsTests.swift`（整体替换：追加一条）

**Interfaces:**
- Consumes: `CaptureResult.annotationsDropped`（Task 4）
- Produces: `ScreenshotActions.perform(_ action: CaptureAction, result: CaptureResult)`；`static func followUpMessage(annotationsDropped: Bool) -> String?`

- [ ] **Step 1: 写失败的测试**

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

    @Test func droppedAnnotationsGetAFollowUpMessage() {
        #expect(ScreenshotActions.followUpMessage(annotationsDropped: true) == "标注未能合成，已输出原图")
        #expect(ScreenshotActions.followUpMessage(annotationsDropped: false) == nil)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `scripts/test.sh`
Expected: 编译失败，`type 'ScreenshotActions' has no member 'followUpMessage'`

- [ ] **Step 3: 写实现**

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
    private let ocrWindow: OCRResultWindowController

    init(settings: ScreenshotSettings, saver: ScreenshotSaver = ScreenshotSaver()) {
        self.settings = settings
        self.saver = saver
        self.ocrWindow = OCRResultWindowController(settings: settings)
        pins.onImageAction = { [weak self] action, image, pointSize in
            self?.perform(action, image: image, pointSize: pointSize, screenRect: nil)
        }
    }

    /// 截图遮罩上选好区域（可能带标注）之后执行操作。
    func perform(_ action: CaptureAction, result: CaptureResult) {
        perform(action, image: result.image, pointSize: result.pointSize, screenRect: result.screenRect)
        if let message = Self.followUpMessage(annotationsDropped: result.annotationsDropped) {
            Toast.show(message)              // 盖掉刚才的"已复制"等提示，让用户知道这张图没带上标注
        }
    }

    /// 标注没能合成上去（极少见：位图上下文创建失败）时的补充提示。
    static func followUpMessage(annotationsDropped: Bool) -> String? {
        annotationsDropped ? "标注未能合成，已输出原图" : nil
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
    private let hotkeys: HotkeySettings
    private let actions: ScreenshotActions
    private var hotkeyObserver: NSObjectProtocol?
    private let guide = ScreenRecordingGuideWindowController()
    private let log = Logger(subsystem: "com.imiros.mykit", category: "screenshot")
    /// 正在进行的截图会话。同一时间只允许一个。
    private var session: CaptureOverlayController?
    /// 已触发、正在定格画面（遮罩还没出现）
    private var isStarting = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hotkeys = HotkeySettings(defaults: defaults)
        self.actions = ScreenshotActions(settings: ScreenshotSettings(defaults: defaults))
        super.init()
        // 用户在设置里改了快捷键 → 菜单上显示的快捷键跟着变
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: HotkeySettings.didChangeNotification, object: defaults, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyShortcutToMenuItem()
            }
        }
    }

    deinit {
        if let hotkeyObserver {
            NotificationCenter.default.removeObserver(hotkeyObserver)
        }
    }

    public func start() throws {}

    public func stop() {
        session?.end()
        actions.pins.closeAll()
    }

    /// 开始一次截图（⇧⌘A 或菜单）。没有"屏幕录制"授权时改为弹出引导窗口。
    public func startCapture() {
        if let session {
            // 保底退出：截图进行中再按一次 ⇧⌘A 直接结束截图。这条路走全局键盘监听，
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
            let controller = CaptureOverlayController(
                snapshots: snapshots, cgWindows: windows, settings: ScreenshotSettings(defaults: defaults))
            controller.onFinish = { [weak self] action, result in
                self?.actions.perform(action, result: result)
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
        let item = NSMenuItem(title: "截图", action: #selector(captureFromMenu), keyEquivalent: "")
        item.target = self
        Self.applyShortcut(hotkeys.screenshotCombo, keyLabel: hotkeys.screenshotKeyLabel, to: item)
        return item
    }()

    /// 截图快捷键的录制状态（设置页用）
    private lazy var recorderModel = HotkeyRecorderModel(
        current: { [hotkeys] in (combo: hotkeys.screenshotCombo, keyLabel: hotkeys.screenshotKeyLabel) },
        save: { [hotkeys] combo, keyLabel in hotkeys.setScreenshot(combo: combo, keyLabel: keyLabel) },
        resetToDefault: { [hotkeys] in hotkeys.resetScreenshot() }
    )

    private func applyShortcutToMenuItem() {
        Self.applyShortcut(hotkeys.screenshotCombo, keyLabel: hotkeys.screenshotKeyLabel, to: captureMenuItem)
    }

    /// 菜单项只能用单个字母 / 数字显示快捷键；F1 之类的功能键就不显示（不影响实际触发）。
    private static func applyShortcut(_ combo: KeyCombo, keyLabel: String, to item: NSMenuItem) {
        if keyLabel.count == 1, let scalar = keyLabel.unicodeScalars.first, CharacterSet.alphanumerics.contains(scalar) {
            item.keyEquivalent = keyLabel.lowercased()
            item.keyEquivalentModifierMask = combo.appKitModifiers
        } else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
        }
    }

    private lazy var closePinsMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "关闭所有贴图", action: #selector(closeAllPinsFromMenu), keyEquivalent: "")
        item.target = self
        return item
    }()

    public var menuItems: [NSMenuItem] {
        [captureMenuItem, closePinsMenuItem]
    }

    public var settingsView: AnyView? {
        AnyView(ScreenshotSettingsView(defaults: defaults, recorder: recorderModel))
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

- [ ] **Step 4: 运行测试，确认通过**

Run: `scripts/test.sh`
Expected: `✔ Test run with 306 tests in 49 suites passed`，零警告。

- [ ] **Step 5: 整体替换 `README.md`**

````markdown
# MyKit

Mac 菜单栏小工具箱。目前的功能：

- **剪切板历史** —— 双击 Option 呼出，保留最近 7 天复制过的文字，可搜索，回车直接粘贴；每条记录前面的图标表示它是从哪个 App 复制的。
- **截图** —— 按 `⇧⌘A`，框选或点选窗口，然后复制 / 保存 / 识别文字 / 贴在屏幕上。

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

**贴图**：拖动可以移动，滚轮缩放，双击关闭；右键有 复制 / 保存 / 识别文字 / 关闭 / 关闭全部贴图。右上角菜单里也有「关闭所有贴图」。

## 修改快捷键

点右上角图标 →「偏好设置…」，改完**立即生效**，不用重启：

- **截图快捷键**：在「截图」一栏点一下显示着 `⇧⌘A` 的按钮 → 它会变成"请按下新的快捷键…" → 按下你想要的组合键即可（按 `Esc` 取消；15 秒不按自动取消）。普通按键必须带 `⌘`、`⌃` 或 `⌥` 之一；`F1`–`F12` 可以单独用。复制 / 粘贴 / 退出这类系统常用键不允许设置。旁边的「恢复默认」会改回 `⇧⌘A`。
- **剪切板呼出方式**：在「剪切板历史」一栏的「呼出方式」里选 双击 Option / 双击 Control / 双击 Command。

**快捷键说明：** `⇧⌘A` 在个别 App 里原本有别的用途（访达里是打开「应用程序」文件夹，Chrome 里是搜索标签页）；MyKit 运行时这个键优先用于截图。钉钉的截图默认也是 `⇧⌘A`，如果按下后出来的是钉钉的截图，到钉钉「设置 → 快捷键」里把截图快捷键关掉或改成别的键。

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

- [ ] **Step 6: 构建并安装**

Run: `scripts/build-app.sh && scripts/install.sh`
Expected: 输出 `designated => identifier "com.imiros.mykit" and certificate leaf = H"…"`（与之前相同，授权不会失效）和 `已安装并启动：/Applications/MyKit.app`。

然后确认启动正常：

```bash
/usr/bin/log show --last 1m --predicate 'subsystem == "com.imiros.mykit"' --info | grep "MyKit 已启动"
```

- [ ] **Step 7: 手动验收（需要人来操作；逐条确认，任何一条不符合就修复后重测）**

每一条都是"做什么 → 应该看到什么"。先按截图快捷键（默认 `⇧⌘A`）框选一块区域。

标注工具：

1. 看选区旁边的工具条。→ 左边多了 9 个图标按钮，鼠标停上去依次显示：方框、椭圆、箭头、直线、画笔、荧光笔、文字、马赛克、序号；中间是撤销、重做（此时是灰的）；右边还是 贴图 / 识别文字 / 保存 / 复制 / ✕。
2. 点「方框」。→ 按钮高亮；工具条旁边多出一行：6 个颜色圆点 + 细 / 中 / 粗；鼠标在选区里变成十字。
3. 在选区里按住拖动。→ 跟着鼠标出现一个红色方框，松手后留在图上；「撤销」按钮变亮。
4. 按住 `Shift` 再拖。→ 画出来的是正方形。换「椭圆」按住 `Shift` → 正圆。
5. 选「箭头」，从左上拖到右下。→ 一支带实心箭头的线。按住 `Shift` 拖 → 方向吸附到水平 / 垂直 / 45°。「直线」同理，只是没有箭头。
6. 选「画笔」随手画一个圈。→ 线条跟手、圆润。
7. 选「荧光笔」在一行文字上横着划过去。→ 半透明的粗线，文字仍然看得清。按住 `Shift` → 是一条笔直的线。
8. 选「文字」，在选区里点一下。→ 出现一个带细边框的输入框，光标在闪。用中文输入法打几个字，**确认候选词窗口能看见**；按回车换行再打一行；点一下别处。→ 输入框消失，文字留在图上，位置没有跳动。
9. 再点一下放一个输入框，什么都不打，按 `Esc`。→ 输入框消失，图上不多出任何东西。
10. 选「马赛克」，在有文字的地方拖一个矩形。→ 矩形里变成方块，看不出原来的字。此时下面那一行**没有颜色圆点**，只有 细 / 中 / 粗；选「粗」再拖一个 → 方块更大。
11. 选「序号」，连点三下。→ 出现 ① ② ③（圆里是数字 1 2 3）。按 `⌘Z` 撤销一个，再点一下 → 新放的是 3，不是 4。
12. 换一种颜色（比如蓝）和粗细（粗），再画一个方框。→ 新画的是蓝色粗线，之前画的不变。选黄色放一个序号 → 圆是黄的、数字是黑的。
13. 从选区里面往选区外面拖一条直线。→ 超出选区的部分看不到（被裁掉）。在选区**外面**按下拖动 → 什么都不发生。

撤销 / 重做 / 取消：

14. 连按几次 `⌘Z`。→ 标注按相反顺序一个个消失。按 `⇧⌘Z` → 一个个回来。撤销两个之后再画一个新的 → 「重做」变灰。工具条上的两个按钮效果相同。
15. 正在输入文字时按 `⌘Z`。→ 撤销的是刚打的字，不是图上的标注。
16. 选着某个工具时按 `Esc`（或点右键）。→ 只是取消选中工具（样式栏消失），标注和选区都还在。再按一次 → 选区和全部标注一起清掉，回到"鼠标移到窗口上会高亮"的状态。再按一次 → 退出截图。

选区锁定：

17. 画了至少一个标注后，取消选中工具，试着拖动选区、拖选区边上的位置、双击选区。→ 选区不动，没有小方块手柄，双击也不会复制。
18. 把标注全部撤销（不选工具）。→ 小方块手柄重新出现，选区又可以移动 / 改大小，双击选区 = 复制。

输出：

19. 画几个标注后按回车（复制），到"预览"里按 `⌘N`（从剪贴板新建）。→ 图上带着全部标注；在 Retina 屏上放大看，线条和文字是清晰的，不发虚；标注的位置和截图时看到的一致。
20. 同样画标注后按 `⌘S`。→ 桌面上的 PNG 带标注。按 `⌘T` → 贴图带标注。
21. 找一段文字：用马赛克遮住其中一行，再在另一行上画一个箭头和一个方框，按 `⌘R`。→ 识别结果里**没有**被马赛克遮住的那一行；画了箭头 / 方框的那一行照常识别出来；截图画面没有关闭，结果面板在选区旁边。点一下定格画面 → 面板收起，标注都还在，可以继续画。

回归（第一期的行为不能坏）：

22. 不选任何工具、不画标注：移动选区、拖 8 个手柄改大小、双击复制、`⌘S` / `⌘T` / `⌘R`、`Esc` 两级取消 —— 全部和以前一样。
23. 识别结果面板上勾选「翻译成中文」。→ 和以前一样工作（截图画面不关闭）。
24. 截图进行中再按一次截图快捷键。→ 直接退出截图（保底退出），哪怕正在输入文字。
25. 选区贴着屏幕底部 / 右边 / 占满全屏时选一个工具。→ 工具条和样式栏都完整地留在屏幕内，互不重叠。
26. 有两块显示器的话：在一块屏上画了标注，再到另一块屏上点一下。→ 第一块屏的选区和标注一起清掉。
27. 连续截图标注十几次后，在"活动监视器"里看 MyKit 的内存。→ 退出截图后回落，不会一路上涨。
28. 退出 MyKit 再打开，截图选一个工具。→ 颜色和粗细是上次选的。

- [ ] **Step 8: Commit**

```bash
git add Sources/ScreenshotModule/ScreenshotActions.swift Sources/ScreenshotModule/ScreenshotModule.swift Tests/ScreenshotModuleTests/ScreenshotActionsTests.swift README.md
git commit -m "feat: annotation tools (screenshot phase 2) - follow-up toast, README and acceptance checklist"
```
