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
        .executableTarget(name: "TartManager", dependencies: ["TartKit"]),
        .testTarget(name: "TartKitTests", dependencies: ["TartKit"]),
    ],
    swiftLanguageModes: [.v5]
)
