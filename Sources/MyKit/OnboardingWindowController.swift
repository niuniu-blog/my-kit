import AppKit
import Core
import SwiftUI

/// 首次启动（或授权被撤销）时的引导窗口。授权完成后由 AppDelegate 调用 close()。
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let view = OnboardingView(needsPasteboardApproval: Permissions.pasteboardNeedsUserApproval)
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "欢迎使用 MyKit"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}

private struct OnboardingView: View {
    let needsPasteboardApproval: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MyKit 需要「辅助功能」权限")
                .font(.title2.bold())
            Text("有了这个权限，MyKit 才能识别你双击 Option，并把选中的内容直接粘贴到你正在用的 App 里。MyKit 不会记录你的键盘输入，也不联网。")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("1. 点击下面的「打开系统设置」")
                Text("2. 在列表里找到 MyKit，打开右边的开关")
                Text("3. 回到这里 —— 授权成功后本窗口会自动关闭")
            }
            .foregroundStyle(.secondary)

            Button("打开系统设置") {
                Permissions.openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)

            if needsPasteboardApproval {
                Divider()
                Text("还需要允许 MyKit 读取剪切板")
                    .font(.headline)
                Text("在「隐私与安全性」里找到「从其他 App 粘贴」，把 MyKit 设为「允许」。否则每次复制，系统都会弹窗询问。")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
                Button("打开隐私与安全性") {
                    Permissions.openPrivacySettings()
                }
            }

            Text("在授权之前，复制记录照常保存；你可以点右上角的 MyKit 图标 →「打开剪切板」查看。")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 460)
    }
}
