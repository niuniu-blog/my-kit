import AppKit
import Core
import SwiftUI

/// 第一次截图时，如果还没有"屏幕录制"授权，就弹这个引导窗口。
@MainActor
final class ScreenRecordingGuideWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "截图需要授权"
            window.contentView = NSHostingView(rootView: ScreenRecordingGuideView())
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct ScreenRecordingGuideView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("截图需要「屏幕录制」权限")
                .font(.title2.bold())
            Text("这是 macOS 对所有截图软件的统一要求（微信、Snipaste 也一样）。MyKit 只在你按下截图快捷键的那一刻读取屏幕画面，不录像、不联网。")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("1. 点击下面的「打开系统设置」")
                Text("2. 在「录屏与系统录音」列表里找到 MyKit，打开右边的开关")
                Text("3. 回到这里，点「重新启动 MyKit」—— 这项权限要重启后才生效")
            }
            .foregroundStyle(.secondary)

            HStack {
                Button("打开系统设置") {
                    Permissions.openScreenRecordingSettings()
                }
                .buttonStyle(.borderedProminent)
                Button("重新启动 MyKit") {
                    Permissions.relaunch()
                }
            }

            Text("没有这项权限不影响剪切板功能。以后系统可能会定期询问「是否继续允许 MyKit 录制屏幕」，选「继续允许」即可。")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 460)
    }
}
