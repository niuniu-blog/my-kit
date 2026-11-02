import AppKit
import Core

/// 代理终端：右上角菜单里的「打开代理终端…」。让 iTerm2 开一个分屏窗口，每块进入各自的文件夹、
/// 执行 proxy 和 curl ip.sb，再和预期 IP 比对。平时零开销，只在检查期间每 0.5 秒读一次屏幕。
@MainActor
public final class ProxyTerminalModule: NSObject, AppModule {
    public let id = "proxyTerminal"
    public let name = "代理终端"

    static let pollInterval: TimeInterval = 0.5

    private let makeDriver: () -> TerminalDriving
    private let passAction: ProxyPassAction
    private var launcher: LauncherWindowController!
    /// 正在检查中的几次（可以同时开好几个窗口）
    private var runs: [ObjectIdentifier: (run: ProxyTerminalRun, timer: Timer)] = [:]

    /// makeDriver / makeStore 只在测试里替换。
    public init(
        makeDriver: @escaping () -> TerminalDriving = { ITermDriver() },
        makeStore: @escaping () -> PresetStore = { PresetStore() },
        passAction: ProxyPassAction = NoPassAction()
    ) {
        self.makeDriver = makeDriver
        self.passAction = passAction
        super.init()
        launcher = LauncherWindowController(makeStore: makeStore) { [weak self] preset in
            self?.launch(preset)
        }
    }

    public func start() throws {}

    public func stop() {
        launcher.close()
        for entry in runs.values {
            entry.timer.invalidate()
        }
        runs.removeAll()
    }

    private lazy var openMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "打开代理终端…", action: #selector(openFromMenu), keyEquivalent: "")
        item.target = self
        return item
    }()

    public var menuItems: [NSMenuItem] {
        [openMenuItem]
    }

    @objc private func openFromMenu() {
        launcher.show()
    }

    func launch(_ preset: TerminalPreset) {
        guard ITermDriver.isInstalled else {
            showAlert("没有找到 iTerm2", "请先安装 iTerm2（https://iterm2.com），装在「应用程序」文件夹里。")
            return
        }
        let run = ProxyTerminalRun(preset: preset, driver: makeDriver(), passAction: passAction)
        do {
            try run.start()
        } catch TerminalError.automationDenied {
            showAutomationDenied()
            return
        } catch {
            showAlert("打开 iTerm2 失败", String(describing: error))
            return
        }

        let key = ObjectIdentifier(run)
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll(key) }
        }
        runs[key] = (run, timer)
    }

    private func poll(_ key: ObjectIdentifier) {
        guard let entry = runs[key], entry.run.poll() else { return }
        entry.timer.invalidate()
        runs[key] = nil
        Toast.show(entry.run.summary, duration: 4)
    }

    private func showAutomationDenied() {
        let alert = NSAlert()
        alert.messageText = "MyKit 没有控制 iTerm2 的权限"
        alert.informativeText = "请在「系统设置 → 隐私与安全性 → 自动化」里，打开 MyKit 下面的 iTerm2 开关，然后再试一次。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
