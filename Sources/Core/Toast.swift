import AppKit

/// 屏幕右上角的小提示（"已复制"之类），约 1.5 秒后淡出。不抢焦点、不挡鼠标。
@MainActor
public enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    /// 提示框位置：可见区域的右上角，距右边 16pt、距顶边 12pt。
    public nonisolated static func frame(for size: CGSize, inVisibleFrame visible: CGRect) -> CGRect {
        CGRect(
            x: visible.maxX - size.width - 16,
            y: visible.maxY - size.height - 12,
            width: size.width,
            height: size.height
        )
    }

    public static func show(_ message: String, duration: TimeInterval = 1.5) {
        hideWork?.cancel()
        panel?.orderOut(nil)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.sizeToFit()
        let size = CGSize(width: label.frame.width + 32, height: label.frame.height + 20)

        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        label.frame.origin = CGPoint(x: 16, y: 10)
        background.addSubview(label)

        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = background

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let screen {
            panel.setFrame(frame(for: size, inVisibleFrame: screen.visibleFrame), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        self.panel = panel

        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                guard let current = Toast.panel, current === panel else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    current.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated {
                        current.orderOut(nil)
                        if Toast.panel === current { Toast.panel = nil }
                    }
                })
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
