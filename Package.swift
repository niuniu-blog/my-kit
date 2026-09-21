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
        .executableTarget(name: "MyKit", dependencies: ["Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "ClipboardModuleTests", dependencies: ["ClipboardModule"]),
    ],
    swiftLanguageModes: [.v5]
)
