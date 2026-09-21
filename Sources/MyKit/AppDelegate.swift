import AppKit
import ClipboardModule
import Core
import ScreenshotModule
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.imiros.mykit", category: "app")
    private let registry = ModuleRegistry()
    private let eventTap = GlobalKeyTap()
    private let hotkeys = HotkeySettings()
    private var hotkeyObservers: [NSObjectProtocol] = []
    private let accessibilityWatcher = AccessibilityWatcher()
    private let onboarding = OnboardingWindowController()
    private var clipboard: ClipboardModule?
    private var screenshot: ScreenshotModule?
    private var statusBar: StatusBarController?
    private var settingsWindow: SettingsWindowController?
    private var eventTapFailed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let clipboard = try ClipboardModule(databaseURL: ClipboardModule.defaultDatabaseURL)
            clipboard.onPausedChange = { [weak self] _ in self?.refreshIcon() }
            registry.register(clipboard)
            self.clipboard = clipboard
        } catch {
            log.error("剪切板模块初始化失败: \(String(describing: error), privacy: .public)")
        }

        let screenshot = ScreenshotModule()
        registry.register(screenshot)
        self.screenshot = screenshot

        registry.startAll()
        for failure in registry.failures {
            log.error("模块 \(failure.id, privacy: .public) 启动失败: \(String(describing: failure.error), privacy: .public)")
        }

        let settingsWindow = SettingsWindowController(modules: registry.modules)
        self.settingsWindow = settingsWindow
        statusBar = StatusBarController(
            moduleMenuItems: registry.menuItemsWithSeparators,
            onOpenSettings: { settingsWindow.show() },
            onMenuWillOpen: { [weak self] in self?.registry.menuWillOpen() },
            onMenuDidClose: { [weak self] in self?.registry.menuDidClose() }
        )

        eventTap.onDoubleTap = { [weak self] in
            self?.clipboard?.togglePanel()
        }
        applyHotkeys()
        observeHotkeySettings()
        accessibilityWatcher.onChange = { [weak self] trusted in
            self?.accessibilityChanged(trusted)
        }
        accessibilityWatcher.start()
        accessibilityChanged(accessibilityWatcher.isTrusted)

        log.info("MyKit 已启动，辅助功能授权=\(self.accessibilityWatcher.isTrusted), 剪切板需用户批准=\(Permissions.pasteboardNeedsUserApproval)")

        if clipboard?.recoveredFromCorruption == true {
            showDatabaseRecoveredAlert()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap.stop()
        accessibilityWatcher.stop()
        registry.stopAll()
    }

    /// 按当前设置（重新）注册快捷键。用户在偏好设置里改完立即调用，无需重启。
    private func applyHotkeys() {
        eventTap.unregisterAll()
        eventTap.doubleTapModifier = hotkeys.clipboardDoubleTap
        eventTap.register(hotkeys.screenshotCombo) { [weak self] in
            self?.screenshot?.startCapture()
        }
    }

    private func observeHotkeySettings() {
        let center = NotificationCenter.default
        hotkeyObservers = [
            center.addObserver(forName: HotkeySettings.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyHotkeys() }
            },
            // 设置页录制新快捷键期间暂停全局监听，否则现有快捷键会被吞掉、录不进去
            center.addObserver(forName: HotkeySettings.recordingDidBeginNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.eventTap.isSuspended = true }
            },
            center.addObserver(forName: HotkeySettings.recordingDidEndNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.eventTap.isSuspended = false }
            },
        ]
    }

    /// 授权状态变化（含启动时的首次检查）：有权限就开始监听双击 Option，没有就弹引导。
    private func accessibilityChanged(_ trusted: Bool) {
        if trusted {
            eventTapFailed = !eventTap.start()
            onboarding.close()
        } else {
            eventTap.stop()
            eventTapFailed = false
            onboarding.show()
        }
        refreshIcon()
    }

    private func refreshIcon() {
        if !accessibilityWatcher.isTrusted || eventTapFailed {
            statusBar?.setIcon(.warning)
        } else if clipboard?.isPaused == true {
            statusBar?.setIcon(.paused)
        } else {
            statusBar?.setIcon(.normal)
        }
    }

    private func showDatabaseRecoveredAlert() {
        let alert = NSAlert()
        alert.messageText = "剪切板历史已重建"
        alert.informativeText = "原来的历史数据库已损坏，MyKit 已将它备份并新建了一个空的历史。备份文件在 ~/Library/Application Support/MyKit/ 里。"
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
