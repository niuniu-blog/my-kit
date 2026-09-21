import AppKit
import Core
import SwiftUI

/// 卸载器：右上角菜单里的「卸载软件…」。平时零开销，窗口关闭后不留任何东西。
@MainActor
public final class UninstallerModule: NSObject, AppModule {
    public let id = "uninstaller"
    public let name = "卸载软件"

    let windowController: UninstallerWindowController

    /// makeDependencies 只在测试里替换。
    public init(makeDependencies: @escaping () -> UninstallerDependencies = { .live() }) {
        self.windowController = UninstallerWindowController(makeDependencies: makeDependencies)
        super.init()
    }

    public func start() throws {}

    public func stop() {
        windowController.close()
    }

    private lazy var openMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "卸载软件…", action: #selector(openFromMenu), keyEquivalent: "")
        item.target = self
        return item
    }()

    public var menuItems: [NSMenuItem] {
        [openMenuItem]
    }

    @objc private func openFromMenu() {
        windowController.show()
    }
}
