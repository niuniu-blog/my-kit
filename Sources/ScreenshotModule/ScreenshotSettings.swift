import Foundation

public struct ScreenshotSettings {
    public static let saveFolderKey = "screenshot.saveFolder"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public static var desktopURL: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// 截图保存到哪个文件夹。未设置时为桌面。
    public var saveFolder: URL {
        get {
            guard let path = defaults.string(forKey: Self.saveFolderKey), !path.isEmpty else {
                return Self.desktopURL
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        nonmutating set {
            defaults.set(newValue.path, forKey: Self.saveFolderKey)
        }
    }
}
