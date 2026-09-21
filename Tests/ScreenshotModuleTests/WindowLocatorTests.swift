import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct WindowLocatorTests {
    private let display = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    private func info(layer: Int = 0, alpha: Double = 1, pid: pid_t = 100, bounds: CGRect) -> [String: Any] {
        [
            kCGWindowLayer as String: layer,
            kCGWindowAlpha as String: alpha,
            kCGWindowOwnerPID as String: pid,
            kCGWindowBounds as String: bounds.dictionaryRepresentation as NSDictionary,
        ]
    }

    @Test func localRectOnPrimaryDisplayIsUnchanged() {
        let rect = WindowLocator.localRect(cgBounds: CGRect(x: 100, y: 50, width: 800, height: 600), displayBounds: display)
        #expect(rect == CGRect(x: 100, y: 50, width: 800, height: 600))
    }

    @Test func localRectIsOffsetBySecondaryDisplayOrigin() {
        let second = CGRect(x: 1600, y: -200, width: 1200, height: 800)
        let rect = WindowLocator.localRect(cgBounds: CGRect(x: 1700, y: -100, width: 500, height: 400), displayBounds: second)
        #expect(rect == CGRect(x: 100, y: 100, width: 500, height: 400))
    }

    @Test func localRectIsClippedToDisplay() {
        let rect = WindowLocator.localRect(cgBounds: CGRect(x: -50, y: 900, width: 300, height: 300), displayBounds: display)
        #expect(rect == CGRect(x: 0, y: 900, width: 250, height: 100))
    }

    @Test func windowOnAnotherDisplayIsDropped() {
        #expect(WindowLocator.localRect(cgBounds: CGRect(x: 2000, y: 0, width: 300, height: 300), displayBounds: display) == nil)
        let rects = WindowLocator.localRects(
            cgWindows: [CGRect(x: 2000, y: 0, width: 300, height: 300), CGRect(x: 10, y: 10, width: 100, height: 100)],
            displayBounds: display
        )
        #expect(rects == [CGRect(x: 10, y: 10, width: 100, height: 100)])
    }

    @Test func topWindowIsTheFrontmostOneContainingThePoint() {
        let front = CGRect(x: 100, y: 100, width: 300, height: 300)
        let back = CGRect(x: 0, y: 0, width: 1000, height: 800)

        #expect(WindowLocator.topWindow(at: CGPoint(x: 200, y: 200), in: [front, back]) == front)
        #expect(WindowLocator.topWindow(at: CGPoint(x: 600, y: 600), in: [front, back]) == back)
        #expect(WindowLocator.topWindow(at: CGPoint(x: 1500, y: 900), in: [front, back]) == nil)
    }

    @Test func parseKeepsOnlyNormalVisibleForeignWindowsInOrder() {
        let list: [[String: Any]] = [
            info(layer: 24, bounds: CGRect(x: 0, y: 0, width: 1600, height: 24)),            // 菜单栏
            info(bounds: CGRect(x: 100, y: 100, width: 800, height: 600)),                   // 普通窗口（最前）
            info(alpha: 0, bounds: CGRect(x: 0, y: 0, width: 500, height: 500)),             // 全透明
            info(pid: 42, bounds: CGRect(x: 0, y: 0, width: 700, height: 700)),              // MyKit 自己
            info(bounds: CGRect(x: 5, y: 5, width: 30, height: 30)),                         // 太小
            info(bounds: CGRect(x: 0, y: 30, width: 1600, height: 900)),                     // 普通窗口（靠后）
        ]

        let result = WindowLocator.parse(list, excludingPID: 42)

        #expect(result == [
            CGRect(x: 100, y: 100, width: 800, height: 600),
            CGRect(x: 0, y: 30, width: 1600, height: 900),
        ])
    }

    @Test func parseSkipsEntriesWithoutBounds() {
        let broken: [String: Any] = [kCGWindowLayer as String: 0]
        #expect(WindowLocator.parse([broken], excludingPID: 1).isEmpty)
    }

    @Test func systemQueryRunsWithoutScreenRecordingPermission() {
        // 只验证不崩溃、结果满足过滤条件；不依赖当前开着哪些窗口
        for bounds in WindowLocator.visibleWindowBounds() {
            #expect(bounds.width >= WindowLocator.minimumWindowSide)
            #expect(bounds.height >= WindowLocator.minimumWindowSide)
        }
    }
}
