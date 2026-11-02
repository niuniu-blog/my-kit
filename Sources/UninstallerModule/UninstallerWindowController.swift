import AppKit
import Core
import SwiftUI

/// 卸载窗口。打开时才创建视图模型和图标缓存；关闭时全部释放，什么都不留在内存里。
@MainActor
final class UninstallerWindowController: NSObject, NSWindowDelegate {
    private let makeDependencies: () -> UninstallerDependencies
    private(set) var window: NSWindow?
    private(set) var model: UninstallerViewModel?

    init(makeDependencies: @escaping () -> UninstallerDependencies) {
        self.makeDependencies = makeDependencies
    }

    var isOpen: Bool { window != nil }

    /// activate = false 只在测试里用（测试进程里没有正在运行的 NSApplication）。
    func show(activate: Bool = true) {
        if window == nil {
            let model = UninstallerViewModel(dependencies: makeDependencies())
            let view = UninstallerView(
                model: model, icons: AppIconStore(), home: FileManager.default.homeDirectoryForCurrentUser)
            let window = EditableWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "卸载软件"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 760, height: 480)
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.delegate = self
            self.window = window
            self.model = model
            model.start()
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
        model?.teardown()
        model = nil
        let closing = window
        window = nil
        closing?.delegate = nil
        // 等系统把关闭流程走完，再放掉界面（连同图标缓存）
        DispatchQueue.main.async {
            closing?.contentView = nil
        }
    }
}
