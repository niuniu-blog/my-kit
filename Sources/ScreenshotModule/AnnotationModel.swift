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
