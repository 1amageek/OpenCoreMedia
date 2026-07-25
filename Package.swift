// swift-tools-version: 6.3

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
        .executableTarget(
            name: "OpenCoreMediaEmbeddedSmoke",
            dependencies: ["OpenCoreMedia"],
            linkerSettings: [
                .linkedLibrary(
                    "swiftUnicodeDataTables",
                    .when(platforms: [.wasi])
                )
            ]
        ),
        .testTarget(
            name: "OpenCoreMediaTests",
            dependencies: ["OpenCoreMedia"]
        )
    ],
    swiftLanguageModes: [.v6]
)
