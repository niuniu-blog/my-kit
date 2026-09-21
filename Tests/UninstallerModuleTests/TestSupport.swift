import Foundation
@testable import UninstallerModule

/// 测试专用的临时目录。所有文件系统测试都只在这里面进行；对象释放时整个目录被清掉。
/// （清理临时目录是测试代码的事；模块的正式代码里不允许出现任何永久删除。）
final class TempDir {
    let url: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("mykit-uninstaller-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.standardizedFileURL
    }

    deinit {
        // 有的测试会把目录改成只读，清理前先改回来
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let item as URL in enumerator {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: item.path)
            }
        }
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func makeDirectory(_ relativePath: String) throws -> URL {
        let target = url.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    @discardableResult
    func makeFile(_ relativePath: String, bytes: Int = 16) throws -> URL {
        let target = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: target)
        return target
    }

    /// 伪造一个 .app：只有 Contents/Info.plist 和一个假的可执行文件。
    @discardableResult
    func makeApp(
        _ relativePath: String,
        bundleID: String?,
        name: String? = nil,
        displayName: String? = nil,
        version: String? = "1.0",
        payloadBytes: Int = 64
    ) throws -> URL {
        let app = try makeDirectory(relativePath)
        var plist: [String: Any] = [:]
        if let bundleID { plist["CFBundleIdentifier"] = bundleID }
        if let name { plist["CFBundleName"] = name }
        if let displayName { plist["CFBundleDisplayName"] = displayName }
        if let version { plist["CFBundleShortVersionString"] = version }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try makeDirectory(relativePath + "/Contents/MacOS")
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data(repeating: 0x42, count: payloadBytes).write(to: app.appendingPathComponent("Contents/MacOS/fake"))
        return app
    }
}
