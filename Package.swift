// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyKit",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Core"),
        .target(
            name: "ClipboardModule",
            dependencies: ["Core"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "ScreenshotModule", dependencies: ["Core"]),
        .target(name: "SystemMonitorModule", dependencies: ["Core"]),
        .target(name: "UninstallerModule", dependencies: ["Core"]),
        .target(name: "ProxyTerminalModule", dependencies: ["Core"]),
        .executableTarget(
            name: "MyKit",
            dependencies: ["Core", "ClipboardModule", "ScreenshotModule", "SystemMonitorModule", "UninstallerModule", "ProxyTerminalModule"]
        ),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "ClipboardModuleTests", dependencies: ["ClipboardModule"]),
        .testTarget(name: "ScreenshotModuleTests", dependencies: ["ScreenshotModule"]),
        .testTarget(name: "SystemMonitorModuleTests", dependencies: ["SystemMonitorModule"]),
        .testTarget(name: "UninstallerModuleTests", dependencies: ["UninstallerModule"]),
        .testTarget(name: "ProxyTerminalModuleTests", dependencies: ["ProxyTerminalModule"]),
    ],
    swiftLanguageModes: [.v5]
)
