import AppKit
import Foundation
import Testing
@testable import UninstallerModule

@MainActor
@Suite struct UninstallerModuleTests {
    /// 完全不碰系统的依赖：空列表，什么都不做。
    private func inertDependencies() -> UninstallerDependencies {
        UninstallerDependencies(
            listApps: { InstalledAppList() },
            scanLeftovers: { _, _, _ in LeftoverScanResult() },
            sizeOf: { _, _ in 0 },
            makeApp: { _ in nil },
            isProtected: { _, _ in true },
            isRunning: { _ in false },
            quit: { _ in true },
            trash: { _, _ in TrashReport() }
        )
    }

    @Test func exposesIdentityAndASingleMenuItemAndNoSettingsPage() {
        let module = UninstallerModule(makeDependencies: inertDependencies)      // 菜单项的 target 是弱引用，模块必须活着

        #expect(module.id == "uninstaller")
        #expect(module.name == "卸载软件")
        #expect(module.menuItems.map(\.title) == ["卸载软件…"])
        #expect(module.menuItems.allSatisfy { $0.target != nil && $0.action != nil })
        #expect(module.settingsView == nil)
    }

    @Test func windowIsCreatedOnDemandAndEverythingIsReleasedOnClose() throws {
        let module = UninstallerModule(makeDependencies: inertDependencies)
        try module.start()
        #expect(!module.windowController.isOpen)                       // 平时什么都不创建

        module.windowController.show(activate: false)
        #expect(module.windowController.isOpen)
        #expect(module.windowController.model != nil)
        #expect(module.windowController.window?.title == "卸载软件")

        module.windowController.close()
        #expect(!module.windowController.isOpen)
        #expect(module.windowController.model == nil)
    }

    @Test func stoppingTheModuleClosesTheWindow() {
        let module = UninstallerModule(makeDependencies: inertDependencies)
        module.windowController.show(activate: false)

        module.stop()

        #expect(!module.windowController.isOpen)
    }

    @Test func reopeningCreatesAFreshModel() {
        let module = UninstallerModule(makeDependencies: inertDependencies)
        module.windowController.show(activate: false)
        let first = module.windowController.model
        module.windowController.close()

        module.windowController.show(activate: false)

        #expect(module.windowController.model != nil)
        #expect(module.windowController.model !== first)
        module.windowController.close()
    }

    @Test func privacyPaneLinksAreDistinctSystemSettingsURLs() {
        let urls = PrivacyPane.allCases.map(\.url.absoluteString)
        #expect(Set(urls).count == 3)
        #expect(urls.allSatisfy { $0.hasPrefix("x-apple.systempreferences:com.apple.preference.security?Privacy_") })
    }
}
