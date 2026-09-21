import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct ScreenGeometryTests {
    @Test func convertsLocalTopLeftRectToAppKitBottomLeftRect() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let local = CGRect(x: 100, y: 50, width: 300, height: 200)

        let result = ScreenGeometry.appKitRect(fromLocal: local, screenFrame: screen)

        #expect(result == CGRect(x: 100, y: 750, width: 300, height: 200))   // y = 1000 - (50 + 200)
    }

    @Test func respectsSecondaryScreenOrigin() {
        let screen = CGRect(x: 1600, y: -200, width: 1200, height: 800)
        let local = CGRect(x: 10, y: 20, width: 100, height: 100)

        let result = ScreenGeometry.appKitRect(fromLocal: local, screenFrame: screen)

        #expect(result == CGRect(x: 1610, y: 480, width: 100, height: 100))  // y = (-200 + 800) - 120
    }
}
