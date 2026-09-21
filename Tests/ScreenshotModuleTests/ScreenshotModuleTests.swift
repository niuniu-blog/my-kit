import AppKit
import Foundation
import Testing
import Core
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

    @Test func menuShortcutFollowsHotkeySettings() {
        let suite = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let module = ScreenshotModule(defaults: defaults)
        let item = module.menuItems[0]

        HotkeySettings(defaults: defaults).setScreenshot(
            combo: KeyCombo(keyCode: 1, modifiers: [.maskControl, .maskAlternate]), keyLabel: "S")
        #expect(item.keyEquivalent == "s")
        #expect(item.keyEquivalentModifierMask == [.control, .option])

        // 功能键在菜单里没法用单个字符表示：不显示快捷键，但不影响实际触发
        HotkeySettings(defaults: defaults).setScreenshot(combo: KeyCombo(keyCode: 122, modifiers: []), keyLabel: "F1")
        #expect(item.keyEquivalent == "")
    }

    @Test func startAndStopDoNotRequirePermissions() throws {
        let module = makeModule()
        try module.start()
        module.stop()
    }
}
