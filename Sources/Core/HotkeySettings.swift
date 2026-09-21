import AppKit
import CoreGraphics

/// 可以用来"双击呼出"的修饰键。不提供 Shift：中文输入法用它切换中英文，容易误触发。
public enum DoubleTapModifier: String, CaseIterable, Identifiable {
    case option, control, command

    public var id: String { rawValue }

    /// 左、右两个实体键的虚拟键码
    public var keyCodes: Set<Int64> {
        switch self {
        case .option: return [58, 61]
        case .control: return [59, 62]
        case .command: return [55, 54]
        }
    }

    public var mask: CGEventFlags {
        switch self {
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .command: return .maskCommand
        }
    }

    public var displayName: String {
        switch self {
        case .option: return "双击 Option (⌥)"
        case .control: return "双击 Control (⌃)"
        case .command: return "双击 Command (⌘)"
        }
    }
}

/// 用户可修改的快捷键。存在 UserDefaults 里；每次修改都会发通知，外壳据此立即重新注册，无需重启。
public struct HotkeySettings {
    /// object = 对应的 UserDefaults
    public static let didChangeNotification = Notification.Name("com.imiros.mykit.hotkeys.didChange")
    /// 设置页正在录制新快捷键：期间全局键盘监听要暂停，否则旧快捷键会被吞掉、录不进去
    public static let recordingDidBeginNotification = Notification.Name("com.imiros.mykit.hotkeys.recordingDidBegin")
    public static let recordingDidEndNotification = Notification.Name("com.imiros.mykit.hotkeys.recordingDidEnd")

    public static let screenshotKeyCodeKey = "hotkey.screenshot.keyCode"
    public static let screenshotModifiersKey = "hotkey.screenshot.modifiers"
    public static let screenshotKeyLabelKey = "hotkey.screenshot.keyLabel"
    public static let clipboardDoubleTapKey = "hotkey.clipboard.doubleTap"

    public static let defaultScreenshotCombo = KeyCombo.shiftCommandA
    public static let defaultScreenshotKeyLabel = "A"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: 截图

    public var screenshotCombo: KeyCombo {
        guard defaults.object(forKey: Self.screenshotKeyCodeKey) != nil else { return Self.defaultScreenshotCombo }
        let keyCode = Int64(defaults.integer(forKey: Self.screenshotKeyCodeKey))
        let raw = UInt64(truncatingIfNeeded: defaults.integer(forKey: Self.screenshotModifiersKey))
        return KeyCombo(keyCode: keyCode, modifiers: CGEventFlags(rawValue: raw).intersection(KeyCombo.relevantModifiers))
    }

    /// 主键的显示文字，例如 "A"、"F1"
    public var screenshotKeyLabel: String {
        guard defaults.object(forKey: Self.screenshotKeyCodeKey) != nil else { return Self.defaultScreenshotKeyLabel }
        return defaults.string(forKey: Self.screenshotKeyLabelKey) ?? KeyLabel.label(keyCode: UInt16(screenshotCombo.keyCode), characters: nil)
    }

    /// 例如 "⇧⌘A"
    public var screenshotDisplay: String {
        screenshotCombo.displayString(keyLabel: screenshotKeyLabel)
    }

    public func setScreenshot(combo: KeyCombo, keyLabel: String) {
        let modifiers = combo.modifiers.intersection(KeyCombo.relevantModifiers)
        defaults.set(Int(combo.keyCode), forKey: Self.screenshotKeyCodeKey)
        defaults.set(Int(modifiers.rawValue), forKey: Self.screenshotModifiersKey)
        defaults.set(keyLabel, forKey: Self.screenshotKeyLabelKey)
        notifyChanged()
    }

    public func resetScreenshot() {
        defaults.removeObject(forKey: Self.screenshotKeyCodeKey)
        defaults.removeObject(forKey: Self.screenshotModifiersKey)
        defaults.removeObject(forKey: Self.screenshotKeyLabelKey)
        notifyChanged()
    }

    // MARK: 剪切板

    public var clipboardDoubleTap: DoubleTapModifier {
        get {
            defaults.string(forKey: Self.clipboardDoubleTapKey).flatMap(DoubleTapModifier.init(rawValue:)) ?? .option
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Self.clipboardDoubleTapKey)
            notifyChanged()
        }
    }

    /// 设置页用 @AppStorage 直接改了 UserDefaults 之后调用
    public func notifyChanged() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: defaults)
    }
}

/// 主键的显示文字
public enum KeyLabel {
    private static let special: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        49: "Space", 36: "↩", 76: "⌤", 48: "⇥", 51: "⌫", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "PageUp", 121: "PageDown",
    ]

    public static func label(keyCode: UInt16, characters: String?) -> String {
        if let name = special[keyCode] { return name }
        if let characters, !characters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return characters.uppercased()
        }
        return "键 \(keyCode)"
    }
}

public enum HotkeyValidation: Equatable {
    case ok
    /// 普通键必须配 ⌘ / ⌃ / ⌥ 之一（只有 ⇧ 不算），否则会抢走正常打字
    case needsModifier
    /// 复制、粘贴、退出这类离不开的系统快捷键
    case reserved
}

public enum HotkeyValidator {
    private static let functionKeys: Set<Int64> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
    /// 单独配 ⌘ 时保留：A C V X Z Q W H M Tab Space
    private static let reservedWithCommand: Set<Int64> = [0, 8, 9, 7, 6, 12, 13, 4, 46, 48, 49]

    public static func validate(keyCode: Int64, modifiers: CGEventFlags) -> HotkeyValidation {
        let relevant = modifiers.intersection(KeyCombo.relevantModifiers)
        let strong = relevant.intersection([.maskCommand, .maskControl, .maskAlternate])
        if strong.isEmpty {
            return functionKeys.contains(keyCode) ? .ok : .needsModifier
        }
        if relevant == [.maskCommand], reservedWithCommand.contains(keyCode) {
            return .reserved
        }
        return .ok
    }
}

/// 设置页里"点一下 → 按下新快捷键"的录制逻辑。界面无关，可测试。
@MainActor
public final class HotkeyRecorderModel: ObservableObject {
    @Published public private(set) var display: String
    @Published public private(set) var isRecording = false
    @Published public private(set) var message: String?

    private let current: () -> (combo: KeyCombo, keyLabel: String)
    private let save: (KeyCombo, String) -> Void
    private let resetToDefault: () -> Void
    private var monitor: Any?
    private var recordingSession = 0

    public init(
        current: @escaping () -> (combo: KeyCombo, keyLabel: String),
        save: @escaping (KeyCombo, String) -> Void,
        resetToDefault: @escaping () -> Void
    ) {
        self.current = current
        self.save = save
        self.resetToDefault = resetToDefault
        let now = current()
        self.display = now.combo.displayString(keyLabel: now.keyLabel)
    }

    /// installMonitor = false 只在测试里用（测试直接调 handleKey）
    public func beginRecording(installMonitor: Bool = true) {
        guard !isRecording else { return }
        isRecording = true
        message = nil
        recordingSession += 1
        NotificationCenter.default.post(name: HotkeySettings.recordingDidBeginNotification, object: self)
        if installMonitor {
            // 保险：录制期间全局快捷键是暂停的。万一用户点了录制就关掉窗口，15 秒后自动取消，
            // 不会让双击 Option / 截图快捷键一直失灵。
            let session = recordingSession
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self, self.isRecording, self.recordingSession == session else { return }
                self.cancelRecording()
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isRecording else { return event }
                self.handleKey(keyCode: event.keyCode, modifiers: event.modifierFlags, characters: event.charactersIgnoringModifiers)
                return nil   // 录制期间按键不再传给窗口
            }
        }
    }

    public func cancelRecording() {
        guard isRecording else { return }
        finishRecording()
    }

    public func handleKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) {
        guard isRecording else { return }
        let flags = KeyCombo.modifiers(from: modifiers)
        if keyCode == 53, flags.isEmpty {      // Esc：取消
            finishRecording()
            return
        }
        switch HotkeyValidator.validate(keyCode: Int64(keyCode), modifiers: flags) {
        case .needsModifier:
            message = "需要同时按住 ⌘、⌃ 或 ⌥（F1–F12 可以单独使用）"
        case .reserved:
            message = "这是系统常用快捷键，换一个吧"
        case .ok:
            let combo = KeyCombo(keyCode: Int64(keyCode), modifiers: flags)
            let label = KeyLabel.label(keyCode: keyCode, characters: characters)
            save(combo, label)
            display = combo.displayString(keyLabel: label)
            finishRecording()
        }
    }

    public func reset() {
        cancelRecording()
        resetToDefault()
        let now = current()
        display = now.combo.displayString(keyLabel: now.keyLabel)
        message = nil
    }

    private func finishRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
        message = nil
        NotificationCenter.default.post(name: HotkeySettings.recordingDidEndNotification, object: self)
    }
}
