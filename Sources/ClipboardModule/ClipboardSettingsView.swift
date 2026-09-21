import Core
import SwiftUI

struct ClipboardSettingsView: View {
    @AppStorage private var retentionDays: Int
    let onClear: () -> Void

    @ViewState private var confirmingClear = false   // 不能写 @State，见 Global Constraints

    init(defaults: UserDefaults, onClear: @escaping () -> Void) {
        _retentionDays = AppStorage(
            wrappedValue: ClipboardSettings.defaultRetentionDays,
            ClipboardSettings.retentionDaysKey,
            store: defaults
        )
        self.onClear = onClear
    }

    var body: some View {
        Stepper(
            "历史保留 \(retentionDays) 天",
            value: $retentionDays,
            in: ClipboardSettings.retentionRange
        )
        Button("清空历史…", role: .destructive) {
            confirmingClear = true
        }
        .confirmationDialog("确定清空全部剪切板历史吗？此操作无法撤销。", isPresented: $confirmingClear) {
            Button("清空", role: .destructive, action: onClear)
            Button("取消", role: .cancel) {}
        }
    }
}
