import Foundation

public struct MonitorSettings {
    public static let showInMenuBarKey = "monitor.showInMenuBar"
    public static let intervalKey = "monitor.interval"
    public static let showNetworkInMenuBarKey = "monitor.showNetworkInMenuBar"
    public static let allowedIntervals = [1, 2, 5]
    public static let defaultInterval = 2
    /// 设置页改了任何一项之后发出；object = 对应的 UserDefaults
    public static let didChangeNotification = Notification.Name("com.imiros.mykit.monitor.settingsDidChange")

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 是否在菜单栏图标旁边显示 "CPU 12%  内存 63%"。默认显示。
    public var showInMenuBar: Bool {
        get {
            guard defaults.object(forKey: Self.showInMenuBarKey) != nil else { return true }
            return defaults.bool(forKey: Self.showInMenuBarKey)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Self.showInMenuBarKey)
            notifyChanged()
        }
    }

    /// 菜单栏文字里是否带上网速（↓下载 ↑上传）。默认带。只在 showInMenuBar 开着时有意义。
    public var showNetworkInMenuBar: Bool {
        get {
            guard defaults.object(forKey: Self.showNetworkInMenuBarKey) != nil else { return true }
            return defaults.bool(forKey: Self.showNetworkInMenuBarKey)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Self.showNetworkInMenuBarKey)
            notifyChanged()
        }
    }

    /// 刷新间隔（秒）：1 / 2 / 5。未设置或存了别的值时为 2。
    public var interval: Int {
        get {
            let stored = defaults.integer(forKey: Self.intervalKey)
            return Self.allowedIntervals.contains(stored) ? stored : Self.defaultInterval
        }
        nonmutating set {
            defaults.set(newValue, forKey: Self.intervalKey)
            notifyChanged()
        }
    }

    /// 设置页用 @AppStorage 直接改了 UserDefaults 之后调用
    public func notifyChanged() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: defaults)
    }
}
