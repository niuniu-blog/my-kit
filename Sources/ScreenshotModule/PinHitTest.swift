import CoreGraphics

/// 捏合手势发生时该缩放哪一张贴图。纯函数。
enum PinHitTest {
    struct Candidate {
        let windowNumber: Int
        /// AppKit 全局坐标
        let frame: CGRect
    }

    /// point：鼠标指针位置（AppKit 全局坐标）。topWindowNumber：系统报告的、该点最上层窗口的编号
    /// （可能属于别的软件）。只有当最上层窗口正是某张贴图、且指针确实在它里面时才返回它；
    /// 拿不到最上层窗口信息时，退而取指针下最新的一张。
    static func index(at point: CGPoint, topWindowNumber: Int?, candidates: [Candidate]) -> Int? {
        if let topWindowNumber {
            guard let index = candidates.firstIndex(where: { $0.windowNumber == topWindowNumber }),
                  candidates[index].frame.contains(point) else { return nil }
            return index
        }
        return candidates.lastIndex { $0.frame.contains(point) }
    }
}
