// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "ZipForge",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "ZipForge", targets: ["ZipForge"]),
        .library(name: "ZipForgeCore", targets: ["ZipForgeCore"])
    ],
    targets: [
        .target(
            name: "ZipForgeCore",
            dependencies: []
        ),
        .target(
            name: "ZipForge",
            dependencies: ["ZipForgeCore"]
        ),
        .testTarget(
            name: "ZipForgeCoreTests",
            dependencies: ["ZipForgeCore"]
        )
    ]
)
