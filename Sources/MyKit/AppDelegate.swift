import AppKit
import Core
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.imiros.mykit", category: "app")
    private let registry = ModuleRegistry()
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        registry.startAll()
        for failure in registry.failures {
            log.error("模块 \(failure.id, privacy: .public) 启动失败: \(String(describing: failure.error), privacy: .public)")
        }
        statusBar = StatusBarController(moduleMenuItems: registry.menuItems, onOpenSettings: {})
        log.info("MyKit 已启动")
    }

    func applicationWillTerminate(_ notification: Notification) {
        registry.stopAll()
    }
}
