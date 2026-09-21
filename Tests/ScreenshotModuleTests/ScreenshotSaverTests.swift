import AppKit
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct ScreenshotSaverTests {
    private let date = Date(timeIntervalSince1970: 1_790_001_125)

    private func makeImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        return try #require(context.makeImage())
    }

    /// 每个测试用自己的临时目录，绝不碰真实的桌面。
    private func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mykit-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func savesPNGIntoFolder() throws {
        let folder = try makeTempFolder()
        let fallback = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: fallback) }
        let saver = ScreenshotSaver(fallbackFolder: fallback, now: { self.date })

        let outcome = saver.save(try makeImage(), pointSize: CGSize(width: 20, height: 10), to: folder)

        guard case .saved(let url) = outcome else {
            Issue.record("expected .saved, got \(outcome)")
            return
        }
        #expect(url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(url.lastPathComponent.hasPrefix("MyKit "))
        #expect(url.pathExtension == "png")
        let decoded = try #require(NSBitmapImageRep(data: try Data(contentsOf: url)))
        #expect(decoded.pixelsWide == 40)
        #expect(decoded.pixelsHigh == 20)
    }

    @Test func secondSaveInSameSecondGetsCounterSuffix() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let saver = ScreenshotSaver(fallbackFolder: folder, now: { self.date })
        let image = try makeImage()

        let first = saver.save(image, pointSize: CGSize(width: 20, height: 10), to: folder)
        let second = saver.save(image, pointSize: CGSize(width: 20, height: 10), to: folder)

        guard case .saved(let firstURL) = first, case .saved(let secondURL) = second else {
            Issue.record("expected both saves to succeed")
            return
        }
        #expect(firstURL != secondURL)
        #expect(secondURL.lastPathComponent.hasSuffix(" (2).png"))
    }

    @Test func fallsBackWhenFolderDoesNotExist() throws {
        let fallback = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: fallback) }
        let missing = fallback.appendingPathComponent("deleted-by-user")
        let saver = ScreenshotSaver(fallbackFolder: fallback, now: { self.date })

        let outcome = saver.save(try makeImage(), pointSize: CGSize(width: 20, height: 10), to: missing)

        guard case .savedToFallback(let url) = outcome else {
            Issue.record("expected .savedToFallback, got \(outcome)")
            return
        }
        #expect(url.deletingLastPathComponent().standardizedFileURL == fallback.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: missing.path))     // 不会自动创建被删掉的文件夹
    }

    @Test func failsWhenFallbackIsAlsoUnavailable() throws {
        let root = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let saver = ScreenshotSaver(fallbackFolder: root.appendingPathComponent("no-fallback"), now: { self.date })

        let outcome = saver.save(try makeImage(), pointSize: CGSize(width: 20, height: 10), to: root.appendingPathComponent("no-folder"))

        #expect(outcome == .failed)
    }

    @Test func failsWithoutRetryWhenFolderIsTheFallbackItself() throws {
        let root = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("gone")
        let saver = ScreenshotSaver(fallbackFolder: missing, now: { self.date })

        #expect(saver.save(try makeImage(), pointSize: CGSize(width: 20, height: 10), to: missing) == .failed)
    }
}
