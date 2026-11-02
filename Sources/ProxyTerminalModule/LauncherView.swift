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
    /// 正在被拖动排序的那一行（拖动过程中随着行的移动更新）
    @ViewState private var draggingRow: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            presetBar
            ipField
            Divider()
            // 中间这块可以滚动：窗口拉小时上面的组合/IP 和下面的按钮始终看得见
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    folderRows
                    LayoutPreview(rows: PaneLayout.rows(count: model.current.folders.count), titles: model.paneTitles)
                    Button {
                        model.addRow()
                    } label: {
                        Label("加一个终端", systemImage: "plus")
                    }
                    .disabled(!model.canAddRow)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .frame(minHeight: 140, maxHeight: .infinity)
            Divider()
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
        .frame(minWidth: 680, maxWidth: .infinity, maxHeight: .infinity)
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
                    alias: Binding(
                        get: { model.alias(at: index) },
                        set: { model.setAlias($0, at: index) }
                    ),
                    defaultName: model.defaultName(at: index),
                    path: Binding(
                        get: { model.displayPath(path) },
                        set: { model.setFolderText($0, at: index) }
                    ),
                    problem: model.folderProblem(at: index),
                    canRemove: model.canRemoveRow,
                    canMoveUp: index > 0,
                    canMoveDown: index < model.current.folders.count - 1,
                    onMove: { model.moveRow(at: index, by: $0) },
                    dragging: $draggingRow,
                    onDragOver: { from in
                        withAnimation(.easeInOut(duration: 0.15)) { model.moveRow(from: from, to: index) }
                    },
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

/// iTerm2 窗口里的排法示意：格子里的数字就是上面列表的行号
private struct LayoutPreview: View {
    let rows: [Int]
    let titles: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("窗口里的排法：")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { row, count in
                    let head = rows[..<row].reduce(0, +)
                    HStack(spacing: 2) {
                        ForEach(0..<count, id: \.self) { column in
                            let index = head + column
                            Text("\(index + 1) \(titles.indices.contains(index) ? titles[index] : "")")
                                .font(.caption2.monospacedDigit())
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, 4)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 16)
                                .background(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary.opacity(0.5)))
                        }
                    }
                }
            }
            .frame(maxWidth: 420)
        }
        .padding(.leading, 6)
    }
}

private struct FolderRow: View {
    let number: Int
    @Binding var alias: String
    let defaultName: String
    @Binding var path: String
    let problem: String?
    let canRemove: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMove: (Int) -> Void
    @Binding var dragging: Int?
    /// 拖着别的行（参数是它现在的行号）经过这一行时：把它挪到这一行的位置
    let onDragOver: (Int) -> Void
    let onChoose: () -> Void
    let onRemove: () -> Void
    let onDrop: (String) -> Void

    @ViewState private var isTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 24)
                .contentShape(Rectangle())
                .help("按住拖动，调整顺序")
                .onDrag {
                    dragging = number - 1
                    return NSItemProvider(object: FolderRow.dragMarker as NSString)
                } preview: {
                    Text("\(number)  \(alias.isEmpty ? defaultName : alias)  \(path)")
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.2)))
                }
            Text("\(number)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            TextField(defaultName, text: $alias)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .help("别名：iTerm2 里这块终端的标题。不填就用文件夹名「\(defaultName)」")
            VStack(alignment: .leading, spacing: 2) {
                TextField("文件夹路径，例如 ~/work/tools", text: $path)
                    .textFieldStyle(.roundedBorder)
                if let problem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("选文件夹…", action: onChoose)
            HStack(spacing: 2) {
                Button { onMove(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(!canMoveUp)
                    .help("往前挪（窗口里往左 / 往上）")
                Button { onMove(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(!canMoveDown)
                    .help("往后挪（窗口里往右 / 往下）")
            }
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
                .fill(isTargeted || dragging == number - 1 ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .onDrop(of: [UTType.fileURL, UTType.plainText], delegate: RowDropDelegate(
            index: number - 1,
            dragging: $dragging,
            isTargeted: $isTargeted,
            onDragOver: onDragOver,
            onDropFolder: acceptDrop
        ))
    }

    static let dragMarker = "mykit-proxy-terminal-row"

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

/// 一行上的拖放：从访达拖来的文件夹 → 填进这一行；拖动别的行 → 排序（经过时就挪过去，松手即定）
private struct RowDropDelegate: DropDelegate {
    let index: Int
    @Binding var dragging: Int?
    @Binding var isTargeted: Bool
    let onDragOver: (Int) -> Void
    let onDropFolder: ([NSItemProvider]) -> Bool

    private func isFolder(_ info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL])
    }

    /// 只认从把手开始的拖动；在输入框里拖选中的文字不算
    private func isRow(_ info: DropInfo) -> Bool {
        !isFolder(info) && dragging != nil && info.hasItemsConforming(to: [UTType.plainText])
    }

    func validateDrop(info: DropInfo) -> Bool {
        isFolder(info) || isRow(info)
    }

    func dropEntered(info: DropInfo) {
        if isFolder(info) {
            isTargeted = true
        } else if isRow(info), let from = dragging, from != index {
            onDragOver(from)
            dragging = index
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: isFolder(info) ? .copy : .move)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        if isFolder(info) {
            return onDropFolder(info.itemProviders(for: [UTType.fileURL]))
        }
        let wasRow = dragging != nil
        dragging = nil
        return wasRow
    }
}
