// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TartManager",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TartKit", targets: ["TartKit"]),
        .executable(name: "TartManager", targets: ["TartManager"]),
    ],
    targets: [
        .target(name: "TartKit"),
        .executableTarget(
            name: "TartManager",
            dependencies: ["TartKit"],
            resources: [.copy("Resources/AppIcon.icns")]
        ),
        .testTarget(name: "TartKitTests", dependencies: ["TartKit"]),
        .testTarget(name: "TartManagerTests", dependencies: ["TartManager", "TartKit"]),
    ],
    swiftLanguageModes: [.v5]
)
