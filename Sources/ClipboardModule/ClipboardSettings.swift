import Foundation

public struct ClipboardSettings {
    public static let retentionDaysKey = "clipboard.retentionDays"
    public static let defaultRetentionDays = 7
    public static let retentionRange = 1...90

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 历史保留天数。未设置时为 7；读取时夹在 1…90 之间。
    public var retentionDays: Int {
        get {
            guard defaults.object(forKey: Self.retentionDaysKey) != nil else { return Self.defaultRetentionDays }
            let stored = defaults.integer(forKey: Self.retentionDaysKey)
            return min(max(stored, Self.retentionRange.lowerBound), Self.retentionRange.upperBound)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Self.retentionDaysKey)
        }
    }
}
