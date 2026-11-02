import Foundation

/// 一套组合：名字、预期 IP、每块终端的文件夹和别名。
public struct TerminalPreset: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var expectedIP: String
    /// 文件夹的完整路径，一行一块终端；同一个文件夹可以出现多次
    public var folders: [String]
    /// 每块终端的别名，和 folders 一一对应；空字符串 = 没起别名（用文件夹名）。
    /// 读的时候用 `paddedAliases`，长度总和 folders 一样。
    public var aliases: [String]

    public init(id: UUID = UUID(), name: String, expectedIP: String = "", folders: [String], aliases: [String] = []) {
        self.id = id
        self.name = name
        self.expectedIP = expectedIP
        self.folders = folders
        self.aliases = aliases
    }

    /// 补齐/截断到和 folders 一样长
    public var paddedAliases: [String] {
        folders.indices.map { aliases.indices.contains($0) ? aliases[$0] : "" }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, expectedIP, folders, aliases
    }

    /// 老版本存的数据没有 aliases，读出来当作都没起别名
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        expectedIP = try container.decode(String.self, forKey: .expectedIP)
        folders = try container.decode([String].self, forKey: .folders)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
    }
}

/// 组合的保存。整组存成一个 JSON，外加"上次用的是哪套"。至少保证有一套。
public final class PresetStore {
    public static let presetsKey = "proxyTerminal.presets"
    public static let lastPresetKey = "proxyTerminal.lastPresetID"

    private let defaults: UserDefaults
    private let home: String

    public init(defaults: UserDefaults = .standard, home: String = NSHomeDirectory()) {
        self.defaults = defaults
        self.home = home
    }

    /// 第一次用时自动建的那套：叫「默认」，一行（主目录），IP 为空
    public func makeDefault() -> TerminalPreset {
        TerminalPreset(name: "默认", folders: [home])
    }

    public func load() -> [TerminalPreset] {
        if let data = defaults.data(forKey: Self.presetsKey),
           let presets = try? JSONDecoder().decode([TerminalPreset].self, from: data),
           !presets.isEmpty {
            return presets
        }
        return [makeDefault()]
    }

    public func save(_ presets: [TerminalPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: Self.presetsKey)
    }

    public var lastPresetID: UUID? {
        get { defaults.string(forKey: Self.lastPresetKey).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Self.lastPresetKey) }
    }
}
