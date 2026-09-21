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

    /// "屏幕录制"授权：截图需要它。授权后必须重启 App 才生效。
    public static var isScreenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 第一次调用会弹出系统提示，并让 MyKit 出现在系统设置的"录屏与系统录音"列表里。
    @discardableResult
    public static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// 重新启动 MyKit：先拉起一个新实例，再退出当前实例。
    @MainActor
    public static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    public static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        NSWorkspace.shared.open(url)
    }
}

/// 定期检查辅助功能授权，变化时回调。用户在系统设置里勾选后无需重启 MyKit。
/// 等待授权时每秒查一次（勾选后马上生效）；已经授权后只需偶尔确认没被撤销，每 5 秒一次，省电。
@MainActor
public final class AccessibilityWatcher {
    public var onChange: ((Bool) -> Void)?
    public private(set) var isTrusted: Bool

    public static let untrustedInterval: TimeInterval = 1.0
    public static let trustedInterval: TimeInterval = 5.0

    private let check: () -> Bool
    private var timer: Timer?
    private var isStarted = false

    public init(check: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.check = check
        self.isTrusted = check()
    }

    /// 当前的检查间隔，取决于是否已经授权
    public var currentInterval: TimeInterval {
        isTrusted ? Self.trustedInterval : Self.untrustedInterval
    }

    public func start() {
        isStarted = true
        scheduleTimer()
    }

    public func stop() {
        isStarted = false
        timer?.invalidate()
        timer = nil
    }

    public func poll() {
        let current = check()
        guard current != isTrusted else { return }
        isTrusted = current
        if isStarted { scheduleTimer() }     // 授权状态变了 → 换成对应的检查间隔
        onChange?(current)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = currentInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
        timer.tolerance = interval / 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
