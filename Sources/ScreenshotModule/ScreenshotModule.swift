import AppKit
import Core
import SwiftUI
import os

@MainActor
public final class ScreenshotModule: NSObject, AppModule {
    public let id = "screenshot"
    public let name = "截图"

    private let defaults: UserDefaults
    private let actions: ScreenshotActions
    private let guide = ScreenRecordingGuideWindowController()
    private let log = Logger(subsystem: "com.imiros.mykit", category: "screenshot")
    /// 正在进行的截图会话。同一时间只允许一个。
    private var session: CaptureOverlayController?
    /// 已触发、正在定格画面（遮罩还没出现）
    private var isStarting = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.actions = ScreenshotActions(settings: ScreenshotSettings(defaults: defaults))
        super.init()
    }

    public func start() throws {}

    public func stop() {
        session?.end()
        actions.pins.closeAll()
    }

    /// 开始一次截图（⌃⌘A 或菜单）。没有"屏幕录制"授权时改为弹出引导窗口。
    public func startCapture() {
        if let session {
            // 保底退出：截图进行中再按一次 ⌃⌘A 直接结束截图。这条路走全局键盘监听，
            // 不依赖遮罩面板拿到键盘焦点，所以即使 Esc 失灵屏幕也不会被卡住。
            session.end()
            return
        }
        guard !isStarting else { return }                      // 正在定格画面：忽略
        guard Permissions.isScreenRecordingGranted else {
            Permissions.requestScreenRecording()              // 让 MyKit 出现在系统设置的列表里
            guide.show()
            return
        }

        isStarting = true
        let screens = ScreenCapturer.currentScreens()
        let windows = WindowLocator.visibleWindowBounds()      // 与定格画面同一时刻的窗口布局
        Task { [weak self] in
            let outcome: Result<[DisplaySnapshot], Error>
            do {
                outcome = .success(try await ScreenCapturer.captureAll(screens: screens))
            } catch {
                outcome = .failure(error)
            }
            self?.captureDidFinish(outcome, windows: windows)
        }
    }

    private func captureDidFinish(_ outcome: Result<[DisplaySnapshot], Error>, windows: [CGRect]) {
        isStarting = false
        switch outcome {
        case .success(let snapshots):
            let controller = CaptureOverlayController(snapshots: snapshots, cgWindows: windows)
            controller.onFinish = { [weak self] action, result in
                self?.actions.perform(action, image: result.image, pointSize: result.pointSize, screenRect: result.screenRect)
            }
            controller.onEnd = { [weak self] in
                self?.session = nil
            }
            session = controller
            controller.begin()
        case .failure(let error):
            log.error("截图失败: \(String(describing: error), privacy: .public)")
            Toast.show("截图失败")
            if !Permissions.isScreenRecordingGranted {
                guide.show()
            }
        }
    }

    // MARK: 菜单与设置

    private lazy var captureMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "截图", action: #selector(captureFromMenu), keyEquivalent: "a")
        item.keyEquivalentModifierMask = [.control, .command]     // 在菜单里显示 ⌃⌘A
        item.target = self
        return item
    }()

    private lazy var closePinsMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "关闭所有贴图", action: #selector(closeAllPinsFromMenu), keyEquivalent: "")
        item.target = self
        return item
    }()

    public var menuItems: [NSMenuItem] {
        [captureMenuItem, closePinsMenuItem]
    }

    public var settingsView: AnyView? {
        AnyView(ScreenshotSettingsView(defaults: defaults))
    }

    @objc private func captureFromMenu() {
        // 等菜单完全收起再定格画面，否则菜单本身会被截进去
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.startCapture()
        }
    }

    @objc private func closeAllPinsFromMenu() {
        actions.pins.closeAll()
    }
}
