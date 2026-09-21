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
