import AppKit
import Core
import SwiftUI

@MainActor
public final class ClipboardModule: NSObject, AppModule {
    public let id = "clipboard"
    public let name = "剪切板历史"
    /// 启动时发现数据库损坏并已重建
    public let recoveredFromCorruption: Bool
    /// 暂停状态变化时通知外壳（用于把菜单栏图标变灰）
    public var onPausedChange: ((Bool) -> Void)?

    private let store: ClipboardStore
    private let settings: ClipboardSettings
    private let defaults: UserDefaults
    private let monitor: ClipboardMonitor
    private let viewModel: ClipboardPanelViewModel
    private let panelController: ClipboardPanelController
    private var purgeTimer: Timer?

    public static var defaultDatabaseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyKit", isDirectory: true)
            .appendingPathComponent("clipboard.sqlite")
    }

    public init(databaseURL: URL, defaults: UserDefaults = .standard) throws {
        let opened = try ClipboardStore.openRecovering(at: databaseURL)
        self.store = opened.store
        self.recoveredFromCorruption = opened.recovered
        self.defaults = defaults
        self.settings = ClipboardSettings(defaults: defaults)
        self.monitor = ClipboardMonitor(pasteboard: NSPasteboard.general, store: opened.store)
        self.viewModel = ClipboardPanelViewModel(store: opened.store)
        self.panelController = ClipboardPanelController(viewModel: viewModel)
        super.init()
    }

    public func start() throws {
        monitor.start()
        purgeExpired()
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.purgeExpired()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        purgeTimer = timer
    }

    public func stop() {
        monitor.stop()
        purgeTimer?.invalidate()
        purgeTimer = nil
    }

    public func togglePanel() {
        panelController.toggle()
    }

    public var isPaused: Bool {
        get { monitor.isPaused }
        set {
            guard newValue != monitor.isPaused else { return }
            monitor.isPaused = newValue
            pauseMenuItem.state = newValue ? .on : .off
            onPausedChange?(newValue)
        }
    }

    // MARK: 菜单与设置

    private lazy var openMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "打开剪切板", action: #selector(openPanelFromMenu), keyEquivalent: "")
        item.target = self
        return item
    }()

    private lazy var pauseMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "暂停记录", action: #selector(togglePausedFromMenu), keyEquivalent: "")
        item.target = self
        return item
    }()

    public var menuItems: [NSMenuItem] {
        [openMenuItem, pauseMenuItem]
    }

    public var settingsView: AnyView? {
        AnyView(ClipboardSettingsView(defaults: defaults, onClear: { [store] in
            Task { try? await store.clearAll() }
        }))
    }

    @objc private func openPanelFromMenu() {
        panelController.show()
    }

    @objc private func togglePausedFromMenu() {
        isPaused.toggle()
    }

    private func purgeExpired() {
        let cutoff = Date().addingTimeInterval(-Double(settings.retentionDays) * 86_400)
        Task { [store] in
            _ = try? await store.purge(olderThan: cutoff)
        }
    }
}
