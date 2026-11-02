import Foundation

/// 一套组合：名字、预期 IP、每块终端的文件夹。
public struct TerminalPreset: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var expectedIP: String
    /// 文件夹的完整路径，一行一块终端；同一个文件夹可以出现多次
    public var folders: [String]

    public init(id: UUID = UUID(), name: String, expectedIP: String = "", folders: [String]) {
        self.id = id
        self.name = name
        self.expectedIP = expectedIP
        self.folders = folders
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
