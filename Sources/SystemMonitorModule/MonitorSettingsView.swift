import SwiftUI

struct MonitorSettingsView: View {
    @AppStorage private var showInMenuBar: Bool
    @AppStorage private var showNetwork: Bool
    @AppStorage private var interval: Int
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        _showInMenuBar = AppStorage(wrappedValue: true, MonitorSettings.showInMenuBarKey, store: defaults)
        _showNetwork = AppStorage(wrappedValue: true, MonitorSettings.showNetworkInMenuBarKey, store: defaults)
        _interval = AppStorage(wrappedValue: MonitorSettings.defaultInterval, MonitorSettings.intervalKey, store: defaults)
    }

    var body: some View {
        Toggle("在菜单栏显示 CPU / 内存", isOn: $showInMenuBar)
            .onChange(of: showInMenuBar) { _, _ in notify() }
        Toggle("同时显示网速（↓下载 ↑上传）", isOn: $showNetwork)
            .onChange(of: showNetwork) { _, _ in notify() }
            .disabled(!showInMenuBar)
        Picker("刷新间隔", selection: $interval) {
            ForEach(MonitorSettings.allowedIntervals, id: \.self) { seconds in
                Text("\(seconds) 秒").tag(seconds)
            }
        }
        .onChange(of: interval) { _, _ in notify() }
        Text("点开右上角菜单可以看到最占 CPU / 内存的 5 个软件；排行只在菜单打开时统计，平时不占资源。")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func notify() {
        MonitorSettings(defaults: defaults).notifyChanged()      // 立即生效，无需重启
    }
}
