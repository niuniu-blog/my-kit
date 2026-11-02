import AppKit
import Core
import SwiftUI
import UniformTypeIdentifiers

struct LauncherView: View {
    @ObservedObject var model: LauncherViewModel
    let onCancel: () -> Void
    let onOpen: (TerminalPreset) -> Void

    private enum NameEdit {
        case create
        case rename
    }

    @ViewState private var nameEdit: NameEdit?
    @ViewState private var nameText = ""
    @ViewState private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            presetBar
            ipField
            Divider()
            folderRows
            Button {
                model.addRow()
            } label: {
                Label("加一个终端", systemImage: "plus")
            }
            .disabled(!model.canAddRow)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("打开") { onOpen(model.current) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canOpen)
            }
        }
        .padding(20)
        .frame(width: 520)
        .frame(minHeight: 300)
        .alert(nameEdit == .create ? "新建组合" : "改名", isPresented: Binding(
            get: { nameEdit != nil },
            set: { if !$0 { nameEdit = nil } }
        )) {
            TextField("组合名字", text: $nameText)
            Button("取消", role: .cancel) {}
            Button("好") {
                if nameEdit == .create {
                    model.createPreset(named: nameText)
                } else {
                    model.renameCurrent(to: nameText)
                }
            }
        } message: {
            Text(nameEdit == .create ? "新组合先复制当前这套的内容，之后再改。" : "")
        }
        .alert("删除组合「\(model.current.name)」？", isPresented: $confirmingDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { model.deleteCurrent() }
        }
    }

    private var presetBar: some View {
        HStack {
            Picker("组合：", selection: Binding(get: { model.selectedID }, set: { model.select($0) })) {
                ForEach(model.presets) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .frame(maxWidth: 240)
            Button("新建") {
                nameText = ""
                nameEdit = .create
            }
            Button("改名") {
                nameText = model.current.name
                nameEdit = .rename
            }
            Button("删除") { confirmingDelete = true }
                .disabled(!model.canDeleteCurrent)
        }
    }

    private var ipField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("预期 IP：")
                TextField("例如 1.2.3.4", text: Binding(get: { model.expectedIP }, set: { model.expectedIP = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
            }
            if let problem = model.ipProblem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var folderRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(model.current.folders.enumerated()), id: \.offset) { index, path in
                FolderRow(
                    number: index + 1,
                    path: model.displayPath(path),
                    problem: model.folderProblem(at: index),
                    canRemove: model.canRemoveRow,
                    onChoose: { chooseFolder(for: index, startingAt: path) },
                    onRemove: { model.removeRow(at: index) },
                    onDrop: { model.setFolder($0, at: index) }
                )
            }
        }
    }

    private func chooseFolder(for index: Int, startingAt path: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.directoryURL = URL(fileURLWithPath: path)
        if panel.runModal() == .OK, let url = panel.url {
            model.setFolder(url.path, at: index)
        }
    }
}

private struct FolderRow: View {
    let number: Int
    let path: String
    let problem: String?
    let canRemove: Bool
    let onChoose: () -> Void
    let onRemove: () -> Void
    let onDrop: (String) -> Void

    @ViewState private var isTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let problem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("选文件夹…", action: onChoose)
            Button(action: onRemove) {
                Image(systemName: "minus")
            }
            .disabled(!canRemove)
            .help("去掉这一行")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            acceptDrop(providers)
        }
    }

    /// 从访达拖进来的文件夹（拖的是文件就用它所在的文件夹）
    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let identifier = UTType.fileURL.identifier
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(identifier) }) else { return false }
        let onDrop = self.onDrop
        provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
            var dropped: URL?
            if let data = item as? Data {
                dropped = URL(dataRepresentation: data, relativeTo: nil)
            } else if let url = item as? URL {
                dropped = url
            }
            guard let dropped else { return }
            let folder = LauncherViewModel.isExistingFolder(dropped.path) ? dropped : dropped.deletingLastPathComponent()
            Task { @MainActor in
                onDrop(folder.path)
            }
        }
        return true
    }
}
