import SwiftUI

/// 设置页里的快捷键录制控件：点一下 → 按下新的组合键 → 立即生效。
public struct HotkeyRecorderView: View {
    @ObservedObject private var model: HotkeyRecorderModel

    public init(model: HotkeyRecorderModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                Button(model.isRecording ? "请按下新的快捷键…" : model.display) {
                    if model.isRecording {
                        model.cancelRecording()
                    } else {
                        model.beginRecording()
                    }
                }
                .frame(minWidth: 150)
                Button("恢复默认") {
                    model.reset()
                }
            }
            if let message = model.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if model.isRecording {
                Text("按 Esc 取消")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            model.cancelRecording()
        }
    }
}
