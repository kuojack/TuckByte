// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "TuckByte",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "TuckByte", targets: ["TuckByte"]),
        .library(name: "TuckByteCore", targets: ["TuckByteCore"]),
        .library(name: "TuckByteIntegration", targets: ["TuckByteIntegration"])
    ],
    targets: [
        .target(
            name: "TuckByteCore",
            dependencies: []
        ),
        .target(
            name: "TuckByteIntegration",
            dependencies: []
        ),
        .target(
            name: "TuckByte",
            dependencies: ["TuckByteCore", "TuckByteIntegration"]
        ),
        .testTarget(
            name: "TuckByteCoreTests",
            dependencies: ["TuckByteCore", "TuckByteIntegration"]
        )
    ]
)
