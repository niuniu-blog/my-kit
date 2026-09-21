import AppKit
import CoreGraphics

public enum PasteService {
    /// 写入剪切板时附带的标记，剪切板监听据此识别"这是 MyKit 自己写的"。
    public static let ownWriteType = NSPasteboard.PasteboardType("com.imiros.mykit.own-write")

    public static func write(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, ownWriteType], owner: nil)
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("1", forType: ownWriteType)
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
