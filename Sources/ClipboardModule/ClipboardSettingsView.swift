import Core
import SwiftUI

struct ClipboardSettingsView: View {
    @AppStorage private var retentionDays: Int
    /// DoubleTapModifier 的 rawValue
    @AppStorage private var doubleTap: String
    private let defaults: UserDefaults
    let onClear: () -> Void

    @ViewState private var confirmingClear = false   // 不能写 @State，见 Global Constraints

    init(defaults: UserDefaults, onClear: @escaping () -> Void) {
        _retentionDays = AppStorage(
            wrappedValue: ClipboardSettings.defaultRetentionDays,
            ClipboardSettings.retentionDaysKey,
            store: defaults
        )
        _doubleTap = AppStorage(
            wrappedValue: DoubleTapModifier.option.rawValue,
            HotkeySettings.clipboardDoubleTapKey,
            store: defaults
        )
        self.defaults = defaults
        self.onClear = onClear
    }

    var body: some View {
        Picker("呼出方式", selection: $doubleTap) {
            ForEach(DoubleTapModifier.allCases) { modifier in
                Text(modifier.displayName).tag(modifier.rawValue)
            }
        }
        .onChange(of: doubleTap) { _, _ in
            HotkeySettings(defaults: defaults).notifyChanged()   // 立即生效，无需重启
        }
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
