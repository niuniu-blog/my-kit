import AppKit
import os

/// 对系统剪切板的只读抽象，测试里用假实现替换。
public protocol PasteboardReading: AnyObject {
    var changeCount: Int { get }
    func currentTypeIdentifiers() -> [String]
    func currentString() -> String?
}

extension NSPasteboard: PasteboardReading {
    public func currentTypeIdentifiers() -> [String] {
        (types ?? []).map(\.rawValue)
    }

    public func currentString() -> String? {
        string(forType: .string)
    }
}

/// macOS 没有剪切板变更通知，只能定时比较 changeCount。
@MainActor
public final class ClipboardMonitor {
    /// 暂停时照常同步 changeCount，但不读取内容，所以暂停期间复制的东西恢复后也不会被补记。
    public var isPaused = false

    private let pasteboard: PasteboardReading
    private let store: ClipboardStore
    private let frontmostApp: () -> (bundleID: String?, name: String?)
    private let now: () -> Date
    private var lastChangeCount: Int
    private var timer: Timer?
    private let log = Logger(subsystem: "com.imiros.mykit", category: "clipboard")

    public init(
        pasteboard: PasteboardReading,
        store: ClipboardStore,
        frontmostApp: @escaping () -> (bundleID: String?, name: String?) = {
            let app = NSWorkspace.shared.frontmostApplication
            return (bundleID: app?.bundleIdentifier, name: app?.localizedName)
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.pasteboard = pasteboard
        self.store = store
        self.frontmostApp = frontmostApp
        self.now = now
        self.lastChangeCount = pasteboard.changeCount   // 启动前就在剪切板里的内容不记录
    }

    public func start(interval: TimeInterval = 0.5) {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.poll()
            }
        }
        timer.tolerance = interval / 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func poll() async {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current          // 先同步再 await，重叠的 poll 不会重复处理同一次变化
        guard !isPaused else { return }

        let decision = CaptureFilter.decide(
            types: pasteboard.currentTypeIdentifiers(),
            string: pasteboard.currentString()
        )
        do {
            switch decision {
            case .record(let text):
                let app = frontmostApp()
                try await store.add(text: text, appBundleID: app.bundleID, appName: app.name, at: now())
            case .touchOwn(let text):
                try await store.touch(text: text, at: now())
            case .skip:
                break
            }
        } catch {
            // 单次写库失败：记日志、丢弃这一条，不打断监听
            log.error("写入剪切板历史失败: \(String(describing: error), privacy: .public)")
        }
    }
}
