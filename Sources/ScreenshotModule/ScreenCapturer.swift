import AppKit
import ScreenCaptureKit

/// 用 ScreenCaptureKit 把每块显示器各定格成一张图。需要"屏幕录制"授权。
public enum ScreenCapturer {
    public enum CaptureError: Error {
        case noDisplayCaptured
    }

    @MainActor
    public static func currentScreens() -> [ScreenDescriptor] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            return ScreenDescriptor(
                displayID: displayID,
                frame: screen.frame,
                cgBounds: CGDisplayBounds(displayID),
                scale: screen.backingScaleFactor
            )
        }
    }

    /// 截图的像素尺寸 = pt 尺寸 × 倍数。
    static func pixelSize(pointSize: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        (Int((pointSize.width * scale).rounded()), Int((pointSize.height * scale).rounded()))
    }

    /// 并发截取所有显示器。某一块失败就跳过；全部失败才抛错。
    public static func captureAll(screens: [ScreenDescriptor]) async throws -> [DisplaySnapshot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let snapshots = await withTaskGroup(of: DisplaySnapshot?.self) { group in
            for screen in screens {
                guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { continue }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let configuration = SCStreamConfiguration()
                let size = pixelSize(pointSize: screen.frame.size, scale: screen.scale)
                configuration.width = size.width
                configuration.height = size.height
                configuration.showsCursor = false
                group.addTask {
                    guard let image = try? await SCScreenshotManager.captureImage(
                        contentFilter: filter, configuration: configuration
                    ) else { return nil }
                    return DisplaySnapshot(screen: screen, image: image)
                }
            }
            var collected: [DisplaySnapshot] = []
            for await snapshot in group {
                if let snapshot { collected.append(snapshot) }
            }
            return collected
        }
        guard !snapshots.isEmpty else { throw CaptureError.noDisplayCaptured }
        return snapshots
    }
}
