import AppKit
import Core

/// 管理面板的显示 / 关闭、键盘操作和粘贴。
@MainActor
final class ClipboardPanelController {
    private let panel: FloatingPanel
    private let viewModel: ClipboardPanelViewModel
    private let isTrusted: () -> Bool

    init(viewModel: ClipboardPanelViewModel, isTrusted: @escaping () -> Bool = { Permissions.isAccessibilityTrusted }) {
        self.viewModel = viewModel
        self.isTrusted = isTrusted
        self.panel = FloatingPanel(size: NSSize(width: 760, height: 460))
        panel.keyHandler = { [weak self] event in
            self?.handleKey(event) ?? false
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if isVisible {
            panel.close()
        } else {
            show()
        }
    }

    func show() {
        Task { [weak self] in
            guard let self else { return }
            await self.viewModel.reset()   // 先加载数据再显示，避免闪一下上次的内容
            self.panel.present(ClipboardPanelView(viewModel: self.viewModel, onPaste: { [weak self] item in
                self?.paste(item)
            }))
        }
    }

    private func paste(_ item: ClipboardItem) {
        if isTrusted() {
            panel.close()
            PasteService.paste(item.text)
        } else {
            PasteService.write(item.text)
            viewModel.footerMessage = "未授予辅助功能权限，已复制，请手动按 ⌘V 粘贴"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.panel.close()
            }
        }
    }

    /// 返回 true 表示按键已处理。
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, !panel.isComposingText else { return false }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let plain = modifiers.isEmpty
        let commandOnly = modifiers == .command

        switch event.keyCode {
        case 125:   // ↓
            if plain { viewModel.moveSelection(by: 1); return true }
        case 126:   // ↑
            if plain { viewModel.moveSelection(by: -1); return true }
        case 36, 76:   // 回车、小键盘回车
            if plain {
                if let item = viewModel.selectedItem { paste(item) }
                return true
            }
        case 53:    // Esc
            panel.close()
            return true
        case 51:    // ⌫
            if commandOnly {
                Task { await viewModel.deleteSelected() }
                return true
            }
        default:
            break
        }

        if commandOnly,
           let characters = event.charactersIgnoringModifiers,
           let number = Int(characters),
           let item = viewModel.item(atShortcut: number) {
            paste(item)
            return true
        }
        return false
    }
}
