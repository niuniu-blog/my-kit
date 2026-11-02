import Foundation

/// 「打开代理终端」小窗口的数据。任何修改立即保存。
@MainActor
public final class LauncherViewModel: ObservableObject {
    @Published public private(set) var presets: [TerminalPreset]
    @Published public private(set) var selectedID: UUID

    private let store: PresetStore
    private let folderExists: (String) -> Bool
    private let home: String

    public init(
        store: PresetStore,
        home: String = NSHomeDirectory(),
        folderExists: @escaping (String) -> Bool = LauncherViewModel.isExistingFolder
    ) {
        self.store = store
        self.home = home
        self.folderExists = folderExists
        let presets = store.load()
        self.presets = presets
        let last = store.lastPresetID
        self.selectedID = presets.first { $0.id == last }?.id ?? presets[0].id
    }

    public nonisolated static func isExistingFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    // MARK: - 当前这套

    public var current: TerminalPreset {
        presets.first { $0.id == selectedID } ?? presets[0]
    }

    public func select(_ id: UUID) {
        guard presets.contains(where: { $0.id == id }) else { return }
        selectedID = id
        store.lastPresetID = id
    }

    public var expectedIP: String {
        get { current.expectedIP }
        set { updateCurrent { $0.expectedIP = newValue } }
    }

    public func setFolder(_ path: String, at index: Int) {
        updateCurrent { preset in
            guard preset.folders.indices.contains(index) else { return }
            preset.folders[index] = path
        }
    }

    /// 加一行，默认和最后一行同一个文件夹
    public func addRow() {
        updateCurrent { preset in
            guard preset.folders.count < PaneLayout.maxPanes else { return }
            preset.folders.append(preset.folders.last ?? home)
        }
    }

    public func removeRow(at index: Int) {
        updateCurrent { preset in
            guard preset.folders.count > 1, preset.folders.indices.contains(index) else { return }
            preset.folders.remove(at: index)
        }
    }

    public var canAddRow: Bool { current.folders.count < PaneLayout.maxPanes }
    public var canRemoveRow: Bool { current.folders.count > 1 }

    // MARK: - 组合

    /// 新建一套：内容复制当前这套，再选中它
    public func createPreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var copy = current
        copy.id = UUID()
        copy.name = trimmed
        presets.append(copy)
        store.save(presets)
        select(copy.id)
    }

    public func renameCurrent(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateCurrent { $0.name = trimmed }
    }

    public var canDeleteCurrent: Bool { presets.count > 1 }

    public func deleteCurrent() {
        guard canDeleteCurrent, let index = presets.firstIndex(where: { $0.id == selectedID }) else { return }
        presets.remove(at: index)
        store.save(presets)
        select(presets[min(index, presets.count - 1)].id)
    }

    // MARK: - 能不能打开

    /// IP 那一栏下面的红字；没问题时为 nil
    public var ipProblem: String? {
        let ip = current.expectedIP.trimmingCharacters(in: .whitespaces)
        if ip.isEmpty { return "请先填预期的 IP" }
        if !IPAddress.isValid(ip) { return "IP 格式不对" }
        return nil
    }

    /// 某一行文件夹的问题；没问题时为 nil
    public func folderProblem(at index: Int) -> String? {
        guard current.folders.indices.contains(index) else { return nil }
        return folderExists(current.folders[index]) ? nil : "文件夹不存在"
    }

    public var canOpen: Bool {
        ipProblem == nil && current.folders.indices.allSatisfy { folderProblem(at: $0) == nil }
    }

    /// 路径显示用：主目录缩写成 ~
    public func displayPath(_ path: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    private func updateCurrent(_ change: (inout TerminalPreset) -> Void) {
        guard let index = presets.firstIndex(where: { $0.id == selectedID }) else { return }
        change(&presets[index])
        store.save(presets)
    }
}
