import AppKit
import Core
import Testing
@testable import SystemMonitorModule

/// 不是断言型测试：设置环境变量 MYKIT_RENDER_DIR 后，把菜单栏上的那张图渲染成 PNG（放大 4 倍）供人眼检查。
/// 平时（没有该环境变量）直接跳过。
@MainActor
@Suite struct MenuBarPreviewRenderTests {
    @Test func rendersPreviewsWhenAsked() throws {
        guard let directory = ProcessInfo.processInfo.environment["MYKIT_RENDER_DIR"] else { return }
        let megabyte: Double = 1_048_576
        let speed = NetworkSpeed(downBytesPerSecond: 1.2 * megabyte, upBytesPerSecond: 56 * 1024)
        let cases: [(String, Double?, Double?, NetworkSpeed?)] = [
            ("normal-net", 12, 63, speed),
            ("warning-net", 91, 86, NetworkSpeed(downBytesPerSecond: 128 * megabyte, upBytesPerSecond: 999 * 1024)),
            ("normal-nonet", 7, 63, nil),
            ("startup", nil, 80, nil),
        ]
        for (name, cpu, memory, network) in cases {
            let title = SystemMonitorModule.attributedTitle(for: MonitorFormat.titleLines(cpu: cpu, memory: memory, network: network))
            let image = try #require(StatusItemImage.compose(symbolName: "square.stack.3d.up", text: title))
            for dark in [false, true] {
                try render(image, dark: dark, to: "\(directory)/\(name)-\(dark ? "dark" : "light").png")
            }
        }
        let iconOnly = try #require(StatusItemImage.compose(symbolName: "square.stack.3d.up", text: nil))
        try render(iconOnly, dark: false, to: "\(directory)/collapsed-light.png")
    }

    private func render(_ image: NSImage, dark: Bool, to path: String) throws {
        let scale: CGFloat = 4
        let padding: CGFloat = 6
        let size = CGSize(width: image.size.width + padding * 2, height: image.size.height + 4)
        func makeRep() throws -> NSBitmapImageRep {
            let rep = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = size
            return rep
        }
        let layer = try makeRep()          // 透明图层：只有图片本身
        let rep = try makeRep()            // 最终结果：背景 + 图层
        let target = NSRect(x: padding, y: 2, width: image.size.width, height: image.size.height)
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        // 第一步：把图片画到透明图层上（模板图在这里手动着色）
        appearance.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: layer)
            image.draw(in: target)
            if image.isTemplate {
                (dark ? NSColor.white : NSColor.black).set()
                target.fill(using: .sourceAtop)
            }
            NSGraphicsContext.current?.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
        }
        // 第二步：背景 + 图层
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        (dark ? NSColor(deviceWhite: 0.16, alpha: 1) : NSColor(deviceWhite: 0.93, alpha: 1)).setFill()
        NSRect(origin: .zero, size: size).fill()
        layer.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: path))
    }
}
