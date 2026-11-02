import AppKit
import Core
import SwiftUI

/// 「打开代理终端」小窗口。每次打开都从保存的设置重新读，关闭后什么都不留。
@MainActor
final class LauncherWindowController: NSObject, NSWindowDelegate {
    private let makeStore: () -> PresetStore
    private let onOpen: (TerminalPreset) -> Void
    private(set) var window: NSWindow?
    private(set) var model: LauncherViewModel?

    init(makeStore: @escaping () -> PresetStore, onOpen: @escaping (TerminalPreset) -> Void) {
        self.makeStore = makeStore
        self.onOpen = onOpen
    }

    var isOpen: Bool { window != nil }

    /// activate = false 只在测试里用（测试进程里没有正在运行的 NSApplication）。
    func show(activate: Bool = true) {
        if window == nil {
            let model = LauncherViewModel(store: makeStore())
            let view = LauncherView(
                model: model,
                onCancel: { [weak self] in self?.close() },
                onOpen: { [weak self] preset in
                    self?.close()
                    self?.onOpen(preset)
                }
            )
            let window = EditableWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "打开代理终端"
            window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: view)
            hosting.sizingOptions = [.minSize]   // 能拖动改大小，但不能小到挤坏内容
            window.contentView = hosting
            window.center()
            // 记住上次拖成的大小和位置，下次打开还是那样
            window.setFrameAutosaveName("ProxyTerminalLauncher")
            window.delegate = self
            self.window = window
            self.model = model
        }
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        model = nil
        let closing = window
        window = nil
        closing?.delegate = nil
        DispatchQueue.main.async {
            closing?.contentView = nil
        }
    }
}
