import AppKit
import CoreGraphics

public enum PasteService {
    /// 写入剪切板时附带的标记，剪切板监听据此识别"这是 MyKit 自己写的"。
    public static let ownWriteType = NSPasteboard.PasteboardType("com.imiros.mykit.own-write")

    /// 由 MyKit 其他功能（例如截图的文字识别）产生的文字会带这个标记；
    /// 剪切板监听据此把来源记为 MyKit 自己，而不是当时碰巧在前台的 App。
    public static let originMarkerType = NSPasteboard.PasteboardType("com.imiros.mykit.origin")

    public static func write(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, ownWriteType], owner: nil)
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("1", forType: ownWriteType)
    }

    /// 写入一段由 MyKit 自己产生的文字。与 write(_:to:) 不同：它**会**作为新记录进入剪切板历史。
    public static func writeFromMyKit(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, originMarkerType], owner: nil)
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("1", forType: originMarkerType)
    }

    /// 写入一张图片（PNG + TIFF 两种格式，兼容各种 App）。pointSize 是图片的 pt 尺寸，用来写入正确的 DPI。
    @discardableResult
    public static func write(image: CGImage, pointSize: CGSize, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let png = ImageEncoding.pngData(from: image, pointSize: pointSize) else { return false }
        let tiff = ImageEncoding.tiffData(from: image, pointSize: pointSize)
        pasteboard.clearContents()
        pasteboard.declareTypes(tiff == nil ? [.png] : [.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        if let tiff {
            pasteboard.setData(tiff, forType: .tiff)
        }
        return true
    }

    /// 向系统事件流发送一次 ⌘V。需要"辅助功能"授权。
    public static func sendPasteKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// 写剪切板，稍等片刻（让面板先关闭、焦点回到原 App），再发送 ⌘V。
    public static func paste(_ text: String, delay: TimeInterval = 0.05) {
        write(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            sendPasteKeystroke()
        }
    }
}
