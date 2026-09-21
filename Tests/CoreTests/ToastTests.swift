import CoreGraphics
import Testing
@testable import Core

@Suite struct ToastTests {
    @Test func frameSitsInTopRightCornerOfVisibleArea() {
        let visible = CGRect(x: 0, y: 0, width: 1600, height: 975)
        let frame = Toast.frame(for: CGSize(width: 120, height: 36), inVisibleFrame: visible)

        #expect(frame.size == CGSize(width: 120, height: 36))
        #expect(frame.maxX == 1584)   // 1600 - 16；注意 #expect 里不要写字面量算式，宏展开后类型推断会出错
        #expect(frame.maxY == 963)    // 975 - 12
    }

    @Test func frameRespectsSecondaryScreenOrigin() {
        let visible = CGRect(x: 1600, y: -300, width: 1200, height: 800)
        let frame = Toast.frame(for: CGSize(width: 100, height: 30), inVisibleFrame: visible)

        #expect(frame.maxX == visible.maxX - 16)
        #expect(frame.maxY == visible.maxY - 12)
    }
}
