import AppKit
import ApplicationServices

public enum Permissions {
    /// "辅助功能"授权：监听双击 Option 和模拟 ⌘V 都需要它。
    public static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    public static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// macOS 15.4 起，系统可以限制 App 在后台读取剪切板。为 true 时需要用户到
    /// "隐私与安全性 → 从其他 App 粘贴"里把 MyKit 设为"允许"。
    public static var pasteboardNeedsUserApproval: Bool {
        if #available(macOS 15.4, *) {
            switch NSPasteboard.general.accessBehavior {
            case .ask, .alwaysDeny:
                return true
            default:
                return false
            }
        }
        return false
    }

    public static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        NSWorkspace.shared.open(url)
    }
}

/// 每秒检查一次辅助功能授权，变化时回调。用户在系统设置里勾选后无需重启 MyKit。
@MainActor
public final class AccessibilityWatcher {
    public var onChange: ((Bool) -> Void)?
    public private(set) var isTrusted: Bool

    private let check: () -> Bool
    private var timer: Timer?

    public init(check: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.check = check
        self.isTrusted = check()
    }

    public func start(interval: TimeInterval = 1.0) {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func poll() {
        let current = check()
        guard current != isTrusted else { return }
        isTrusted = current
        onChange?(current)
    }
}
