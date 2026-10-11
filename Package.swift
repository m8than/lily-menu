// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LilyMenu",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "LilyMenu", targets: ["LilyMenu"]),
    ],
    targets: [
        .target(name: "LilyMenuCore"),
        .executableTarget(name: "LilyMenu", dependencies: ["LilyMenuCore"]),
        .testTarget(name: "LilyMenuCoreTests", dependencies: ["LilyMenuCore"]),
    ]
)
