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

    /// 在输入框里直接打/粘贴的路径：开头的 ~ 换成主目录，去掉粘贴带进来的换行
    public func setFolderText(_ text: String, at index: Int) {
        setFolder(expandPath(text.trimmingCharacters(in: .newlines)), at: index)
    }

    /// 「~」「~/xxx」展开成主目录下的完整路径，其他原样返回
    public func expandPath(_ text: String) -> String {
        if text == "~" { return home }
        if text.hasPrefix("~/") { return home + text.dropFirst(1) }
        return text
    }

    /// 第 index 块终端的别名（没起就是空字符串）
    public func alias(at index: Int) -> String {
        let aliases = current.paddedAliases
        return aliases.indices.contains(index) ? aliases[index] : ""
    }

    public func setAlias(_ alias: String, at index: Int) {
        updateCurrent { preset in
            guard preset.aliases.indices.contains(index) else { return }
            preset.aliases[index] = alias.trimmingCharacters(in: .newlines)
        }
    }

    /// 没起别名时显示的名字（输入框里的灰字）
    public func defaultName(at index: Int) -> String {
        guard current.folders.indices.contains(index) else { return "" }
        return PaneLayout.defaultName(forFolder: current.folders[index])
    }

    /// 每块终端在 iTerm2 里的标题，和打开时用的一样
    public var paneTitles: [String] {
        PaneLayout.titles(forFolders: current.folders, aliases: current.paddedAliases)
    }

    /// 加一行，默认和最后一行同一个文件夹
    public func addRow() {
        updateCurrent { preset in
            guard preset.folders.count < PaneLayout.maxPanes else { return }
            preset.folders.append(preset.folders.last ?? home)
            preset.aliases.append("")
        }
    }

    public func removeRow(at index: Int) {
        updateCurrent { preset in
            guard preset.folders.count > 1, preset.folders.indices.contains(index) else { return }
            preset.folders.remove(at: index)
            preset.aliases.remove(at: index)
        }
    }

    /// 把第 index 行往上（offset = -1）或往下（offset = 1）挪一格
    public func moveRow(at index: Int, by offset: Int) {
        moveRow(from: index, to: index + offset)
    }

    /// 把第 from 行挪到第 to 行的位置（拖动排序用），中间的行顺次让开
    public func moveRow(from: Int, to: Int) {
        updateCurrent { preset in
            guard from != to, preset.folders.indices.contains(from), preset.folders.indices.contains(to) else { return }
            preset.folders.insert(preset.folders.remove(at: from), at: to)
            preset.aliases.insert(preset.aliases.remove(at: from), at: to)
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
        if current.folders[index].trimmingCharacters(in: .whitespaces).isEmpty { return "请填文件夹路径" }
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
        presets[index].aliases = presets[index].paddedAliases   // 先对齐，增删挪行时两边一起动
        change(&presets[index])
        store.save(presets)
    }
}
