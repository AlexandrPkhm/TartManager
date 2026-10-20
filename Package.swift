// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TartManager",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TartKit", targets: ["TartKit"]),
        .executable(name: "TartManager", targets: ["TartManager"]),
    ],
    dependencies: [
        // The in-app updater. Pinned exactly; see AGENTS.md → Dependency Management.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "TartKit"),
        .executableTarget(
            name: "TartManager",
            dependencies: ["TartKit", .product(name: "Sparkle", package: "Sparkle")],
            resources: [.copy("Resources/AppIcon.icns")]
        ),
        .testTarget(name: "TartKitTests", dependencies: ["TartKit"]),
        .testTarget(name: "TartManagerTests", dependencies: ["TartManager", "TartKit"]),
    ],
    swiftLanguageModes: [.v5]
)
