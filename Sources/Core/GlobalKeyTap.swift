import CoreGraphics
import Foundation
import os

/// 全局键盘监听：检测"双击 Option"，以及已注册的组合键（如 ⇧⌘A）。需要"辅助功能"授权。
/// 所有回调都发生在主线程（事件源加在主 RunLoop 上）。
public final class GlobalKeyTap {
    public var onDoubleTap: (() -> Void)?
    /// 检测哪个修饰键的双击（默认 Option）
    public var doubleTapModifier: DoubleTapModifier = .option {
        didSet { detector = DoubleTapDetector() }
    }
    /// 为 true 时所有按键原样放行、不触发任何回调。设置页录制新快捷键期间使用。
    public var isSuspended = false {
        didSet { detector = DoubleTapDetector() }
    }

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var detector = DoubleTapDetector()
    private var registrations: [(combo: KeyCombo, handler: () -> Void)] = []
    private let log = Logger(subsystem: "com.imiros.mykit", category: "hotkey")

    public init() {}

    public var isRunning: Bool { port != nil }

    /// 注册一个组合键。按下时调用 handler，并且**吞掉**这次按键（前台 App 收不到）。
    /// 可以在 start() 之前或之后调用。
    public func register(_ combo: KeyCombo, handler: @escaping () -> Void) {
        registrations.append((combo: combo, handler: handler))
    }

    /// 清空已注册的组合键（用户改了快捷键之后重新注册前调用）。
    public func unregisterAll() {
        registrations.removeAll()
    }

    /// 返回 false 表示创建失败（通常是还没有辅助功能授权）。
    @discardableResult
    public func start() -> Bool {
        if port != nil { return true }

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            if let userInfo {
                let tap = Unmanaged<GlobalKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
                if tap.handle(type: type, event: event) {
                    return nil   // 已注册的组合键：吞掉
                }
            }
            return Unmanaged.passUnretained(event)   // 其余事件原样放行
        }
        // .defaultTap 只需要"辅助功能"授权；.listenOnly 会额外要求"输入监控"，而且无法吞掉事件
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log.error("创建事件监听失败（未授予辅助功能权限？）")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        detector = DoubleTapDetector()
        return true
    }

    public func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(port)
        self.port = nil
        self.source = nil
    }

    /// 返回 true 表示这个事件要被吞掉。
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // 系统会在回调太慢或用户输入安全内容时停用监听，这里立刻重新启用
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        }

        if isSuspended { return false }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if let translated = ModifierEventTranslator.translate(type: type, keyCode: keyCode, flags: flags, target: doubleTapModifier),
           detector.handle(translated, at: ProcessInfo.processInfo.systemUptime) {
            onDoubleTap?()
        }

        for registration in registrations
        where KeyComboMatcher.matches(registration.combo, type: type, keyCode: keyCode, flags: flags) {
            // 按住不放产生的自动重复：照样吞掉，但只在第一次按下时触发
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                registration.handler()
            }
            return true
        }
        return false
    }
}
