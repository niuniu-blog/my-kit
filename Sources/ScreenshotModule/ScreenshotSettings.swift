import Foundation

public struct ScreenshotSettings {
    public static let saveFolderKey = "screenshot.saveFolder"
    public static let autoTranslateKey = "screenshot.autoTranslate"

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

    /// 识别结果面板上"翻译成中文"的勾选状态：勾上后每次识别完自动翻译，直到取消。
    public var autoTranslate: Bool {
        get { defaults.bool(forKey: Self.autoTranslateKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.autoTranslateKey) }
    }
}
