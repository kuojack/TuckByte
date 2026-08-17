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
            name: "CMinizip",
            path: "Sources/CMinizip",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("minizip"),
                .define("HAVE_STDINT_H"),
                .define("HAVE_INTTYPES_H"),
                .define("HAVE_FSEEKO"),
                .define("HAVE_ZLIB"),
                .define("ZLIB_COMPAT"),
                .define("HAVE_PKCRYPT"),
                .define("HAVE_WZAES"),
                .define("HAVE_ARC4RANDOM_BUF"),
                .define("_DARWIN_C_SOURCE"),
                .define("_POSIX_C_SOURCE", to: "200809L"),
                .define("_BSD_SOURCE"),
                .define("_DEFAULT_SOURCE")
            ],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security")
            ]
        ),
        .target(
            name: "TuckByteCore",
            dependencies: ["CMinizip"]
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
