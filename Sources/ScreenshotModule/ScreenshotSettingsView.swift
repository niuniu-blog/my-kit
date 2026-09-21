import AppKit
import SwiftUI

struct ScreenshotSettingsView: View {
    /// 空字符串 = 还没设置过 = 桌面
    @AppStorage private var folderPath: String

    init(defaults: UserDefaults) {
        _folderPath = AppStorage(wrappedValue: "", ScreenshotSettings.saveFolderKey, store: defaults)
    }

    var body: some View {
        LabeledContent("快捷键") {
            Text("⇧⌘A")
                .foregroundStyle(.secondary)
        }
        LabeledContent("保存位置") {
            HStack {
                Text(folderName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Button("选择…", action: chooseFolder)
            }
        }
    }

    private var folderName: String {
        folderPath.isEmpty ? "桌面" : FileManager.default.displayName(atPath: folderPath)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择截图保存到哪个文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
        }
    }
}
