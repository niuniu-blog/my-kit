import Core
import CoreGraphics
import Foundation

public enum SaveOutcome: Equatable {
    case saved(URL)
    /// 指定文件夹写不进去，已改存到后备文件夹（桌面）
    case savedToFallback(URL)
    case failed
}

public struct ScreenshotSaver {
    private let fallbackFolder: URL
    private let now: () -> Date

    /// fallbackFolder 默认是桌面；测试里传临时目录，避免往真实桌面写文件。
    public init(fallbackFolder: URL = ScreenshotSettings.desktopURL, now: @escaping () -> Date = Date.init) {
        self.fallbackFolder = fallbackFolder
        self.now = now
    }

    public func save(_ image: CGImage, pointSize: CGSize, to folder: URL) -> SaveOutcome {
        guard let data = ImageEncoding.pngData(from: image, pointSize: pointSize) else { return .failed }
        if let url = write(data, into: folder) {
            return .saved(url)
        }
        if folder.standardizedFileURL != fallbackFolder.standardizedFileURL,
           let url = write(data, into: fallbackFolder) {
            return .savedToFallback(url)
        }
        return .failed
    }

    /// 文件夹不存在时不会自动创建（那通常意味着用户把它删了或移走了），直接算失败。
    private func write(_ data: Data, into folder: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        let name = ScreenshotFileNamer.fileName(for: now()) { candidate in
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path)
        }
        let url = folder.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
