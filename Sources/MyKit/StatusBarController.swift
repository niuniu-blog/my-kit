import AppKit

/// 屏幕右上角的 MyKit 图标。给 NSStatusItem 设置 menu 后，系统对左键和右键都会弹出同一个菜单。
@MainActor
final class StatusBarController: NSObject {
    enum IconState { case normal, paused, warning }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onOpenSettings: () -> Void

    init(moduleMenuItems: [NSMenuItem], onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        super.init()

        let menu = NSMenu()
        for moduleItem in moduleMenuItems {
            menu.addItem(moduleItem)
        }
        if !moduleMenuItems.isEmpty {
            menu.addItem(.separator())
        }
        let settings = NSMenuItem(title: "偏好设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 MyKit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        setIcon(.normal)
    }

    func setIcon(_ state: IconState) {
        let symbol = state == .warning ? "exclamationmark.triangle" : "square.stack.3d.up"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MyKit")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.appearsDisabled = (state == .paused)
    }

    @objc private func openSettings() {
        onOpenSettings()
    }
}
