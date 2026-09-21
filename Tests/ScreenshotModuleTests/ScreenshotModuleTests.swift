import AppKit
import Foundation
import Testing
@testable import ScreenshotModule

@MainActor
@Suite struct ScreenshotModuleTests {
    private func makeModule() -> ScreenshotModule {
        let suite = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ScreenshotModule(defaults: defaults)
    }

    @Test func exposesIdentityAndSettings() {
        let module = makeModule()
        #expect(module.id == "screenshot")
        #expect(module.name == "截图")
        #expect(module.settingsView != nil)
    }

    @Test func menuHasCaptureWithShortcutAndCloseAllPins() {
        let module = makeModule()      // 菜单项的 target 是弱引用，模块必须活着
        let items = module.menuItems

        #expect(items.map(\.title) == ["截图", "关闭所有贴图"])
        #expect(items[0].keyEquivalent == "a")
        #expect(items[0].keyEquivalentModifierMask == [.shift, .command])
        #expect(items.allSatisfy { $0.target != nil && $0.action != nil })
    }

    @Test func startAndStopDoNotRequirePermissions() throws {
        let module = makeModule()
        try module.start()
        module.stop()
    }
}
