// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "ZipForge",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "ZipForge", targets: ["ZipForge"]),
        .library(name: "ZipForgeCore", targets: ["ZipForgeCore"]),
        .library(name: "ZipForgeIntegration", targets: ["ZipForgeIntegration"])
    ],
    targets: [
        .target(
            name: "ZipForgeCore",
            dependencies: []
        ),
        .target(
            name: "ZipForgeIntegration",
            dependencies: []
        ),
        .target(
            name: "ZipForge",
            dependencies: ["ZipForgeCore", "ZipForgeIntegration"]
        ),
        .testTarget(
            name: "ZipForgeCoreTests",
            dependencies: ["ZipForgeCore", "ZipForgeIntegration"]
        )
    ]
)
