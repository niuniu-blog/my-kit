import AppKit

/// 屏幕右上角的 MyKit 图标（以及图标右边可选的一段文字）。
/// 给 NSStatusItem 设置 menu 后，系统对左键和右键都会弹出同一个菜单。
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    enum IconState { case normal, paused, warning }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onOpenSettings: () -> Void
    private let onMenuWillOpen: () -> Void
    private let onMenuDidClose: () -> Void

    /// moduleMenuItems：各模块的菜单项，已经带好分隔线（见 ModuleRegistry.menuItemsWithSeparators）。
    init(
        moduleMenuItems: [NSMenuItem],
        onOpenSettings: @escaping () -> Void,
        onMenuWillOpen: @escaping () -> Void = {},
        onMenuDidClose: @escaping () -> Void = {}
    ) {
        self.onOpenSettings = onOpenSettings
        self.onMenuWillOpen = onMenuWillOpen
        self.onMenuDidClose = onMenuDidClose
        super.init()

        let menu = NSMenu()
        for moduleItem in moduleMenuItems {
            menu.addItem(moduleItem)
        }
        let settings = NSMenuItem(title: "偏好设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 MyKit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self

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

    /// 图标右边的文字（系统监控的 "CPU 12%  内存 63%"）。传 nil 则只显示图标。
    func setTitle(_ title: NSAttributedString?) {
        guard let button = item.button else { return }
        if let title, title.length > 0 {
            button.attributedTitle = title
            button.imagePosition = .imageLeft
        } else {
            button.attributedTitle = NSAttributedString()
            button.imagePosition = .imageOnly
        }
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        onMenuWillOpen()
    }

    func menuDidClose(_ menu: NSMenu) {
        onMenuDidClose()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }
}
