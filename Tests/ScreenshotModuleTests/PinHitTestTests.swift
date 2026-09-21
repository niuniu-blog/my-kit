import CoreGraphics
import Testing
@testable import ScreenshotModule

/// 捏合手势发生时，该缩放哪一张贴图：鼠标指针下面、最上层的那一张
@Suite struct PinHitTestTests {
    private let pins: [PinHitTest.Candidate] = [
        .init(windowNumber: 11, frame: CGRect(x: 100, y: 100, width: 300, height: 200)),
        .init(windowNumber: 22, frame: CGRect(x: 250, y: 150, width: 300, height: 200)),   // 和上一张部分重叠
    ]

    @Test func picksThePinThatIsTheTopWindowUnderTheCursor() {
        let overlap = CGPoint(x: 300, y: 200)
        #expect(PinHitTest.index(at: overlap, topWindowNumber: 22, candidates: pins) == 1)
        #expect(PinHitTest.index(at: overlap, topWindowNumber: 11, candidates: pins) == 0)
    }

    @Test func ignoresThePinWhenAnotherAppsWindowCoversItAtThatPoint() {
        #expect(PinHitTest.index(at: CGPoint(x: 150, y: 150), topWindowNumber: 999, candidates: pins) == nil)
    }

    @Test func cursorOutsideEveryPinMeansNoTarget() {
        #expect(PinHitTest.index(at: CGPoint(x: 10, y: 10), topWindowNumber: 11, candidates: pins) == nil)
    }

    @Test func topWindowMustAlsoContainTheCursor() {
        // 窗口号对上了但指针其实不在它的范围内（数据不一致）→ 不缩放
        #expect(PinHitTest.index(at: CGPoint(x: 560, y: 360), topWindowNumber: 11, candidates: pins) == nil)
    }

    @Test func withoutTopWindowInformationFallsBackToTheNewestPinUnderTheCursor() {
        #expect(PinHitTest.index(at: CGPoint(x: 300, y: 200), topWindowNumber: nil, candidates: pins) == 1)
        #expect(PinHitTest.index(at: CGPoint(x: 120, y: 120), topWindowNumber: nil, candidates: pins) == 0)
    }
}
