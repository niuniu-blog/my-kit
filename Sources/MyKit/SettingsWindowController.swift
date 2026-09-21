import AppKit
import Core
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let modules: [AppModule]

    init(modules: [AppModule]) {
        self.modules = modules
    }

    func show() {
        if window == nil {
            let sections = modules.compactMap { module in
                module.settingsView.map { SettingsSection(id: module.id, title: module.name, view: $0) }
            }
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "MyKit 偏好设置"
            window.contentView = NSHostingView(rootView: SettingsView(sections: sections))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsSection: Identifiable {
    let id: String
    let title: String
    let view: AnyView
}

private struct SettingsView: View {
    let sections: [SettingsSection]

    var body: some View {
        Form {
            Section("通用") {
                LaunchAtLoginToggle()
            }
            ForEach(sections) { section in
                Section(section.title) {
                    section.view
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LaunchAtLoginToggle: View {
    // 不能写 @State，见 Global Constraints
    @ViewState private var enabled = SMAppService.mainApp.status == .enabled
    @ViewState private var errorText: String?

    var body: some View {
        Toggle("开机自动启动", isOn: $enabled)
            .onChange(of: enabled) { _, newValue in
                guard newValue != (SMAppService.mainApp.status == .enabled) else { return }
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    errorText = nil
                } catch {
                    errorText = "设置失败：\(error.localizedDescription)"
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
        if let errorText {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}
