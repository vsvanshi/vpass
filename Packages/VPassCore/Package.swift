// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VPassCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "VPassCore", targets: ["VPassCore"])
    ],
    targets: [
        .target(name: "VPassCore"),
        .testTarget(
            name: "VPassCoreTests",
            dependencies: ["VPassCore"]
        )
    ]
)
