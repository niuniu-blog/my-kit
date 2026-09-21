import AppKit
import Core
import SwiftUI

/// "识别结果"窗口。普通窗口（会激活 MyKit，因为要打字）；每次识别复用同一个窗口。
@MainActor
final class OCRResultWindowController {
    private let model = OCRResultModel(
        recognize: { try await TextRecognizer.recognize($0) },
        copy: { PasteService.writeFromMyKit($0) }
    )
    private var window: NSWindow?

    func recognize(_ image: CGImage) {
        show()
        Task { await model.run(on: image) }
    }

    private func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "识别结果"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 320, height: 200)
            window.contentView = NSHostingView(rootView: OCRResultView(model: model, onClose: { [weak window] in
                window?.close()
            }))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct OCRResultView: View {
    @ObservedObject var model: OCRResultModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $model.text)
                .font(.system(size: 14))
                .padding(8)
                .overlay {
                    if model.isRecognizing {
                        ProgressView()
                    }
                }
            Divider()
            HStack {
                Text(model.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("重新复制") { model.copyCurrentText() }
                    .disabled(model.text.isEmpty)
                Button("关闭", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 320, minHeight: 200)
    }
}
