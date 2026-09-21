import CoreGraphics
import Foundation
import os

/// 全局监听键盘事件，检测到双击 Option 时回调。需要"辅助功能"授权。
/// 回调发生在主线程（事件源加在主 RunLoop 上）。
public final class ModifierEventTap {
    public var onDoubleTap: (() -> Void)?

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var detector = DoubleTapDetector()
    private let log = Logger(subsystem: "com.imiros.mykit", category: "hotkey")

    public init() {}

    public var isRunning: Bool { port != nil }

    /// 返回 false 表示创建失败（通常是还没有辅助功能授权）。
    @discardableResult
    public func start() -> Bool {
        if port != nil { return true }

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            if let userInfo {
                let tap = Unmanaged<ModifierEventTap>.fromOpaque(userInfo).takeUnretainedValue()
                tap.handle(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)   // 永远原样放行，不修改也不吞掉事件
        }
        // .defaultTap 只需要"辅助功能"授权；.listenOnly 会额外要求"输入监控"
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

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // 系统会在回调太慢或用户输入安全内容时停用监听，这里立刻重新启用
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return
        }
        let translated = ModifierEventTranslator.translate(
            type: type,
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            flags: event.flags
        )
        guard let translated else { return }
        if detector.handle(translated, at: ProcessInfo.processInfo.systemUptime) {
            onDoubleTap?()
        }
    }
}
