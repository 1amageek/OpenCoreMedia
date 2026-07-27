// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "OpenCoreMedia",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "OpenCoreMedia",
            targets: ["OpenCoreMedia"]
        ),
        .library(
            name: "OpenCoreMediaFoundation",
            targets: ["OpenCoreMediaFoundation"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/1amageek/OpenCoreVideo.git",
            branch: "main"
        )
    ],
    targets: [
        .target(
            name: "OpenCoreMedia",
            dependencies: ["OpenCoreVideo"]
        ),
        .target(
            name: "OpenCoreMediaFoundation",
            dependencies: ["OpenCoreMedia"]
        ),
        .executableTarget(
            name: "OpenCoreMediaEmbeddedSmoke",
            dependencies: ["OpenCoreMedia"],
            path: "Tests/Runtime/OpenCoreMediaEmbeddedSmoke",
            linkerSettings: [
                .linkedLibrary(
                    "swiftUnicodeDataTables",
                    .when(platforms: [.wasi])
                )
            ]
        ),
        .executableTarget(
            name: "OpenCoreMediaBlockBufferSmoke",
            dependencies: ["OpenCoreMedia"],
            path: "Tests/Runtime/OpenCoreMediaBlockBufferSmoke"
        ),
        .testTarget(
            name: "OpenCoreMediaTests",
            dependencies: [
                "OpenCoreMedia",
                "OpenCoreMediaFoundation"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
