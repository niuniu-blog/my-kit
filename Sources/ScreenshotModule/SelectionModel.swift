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
