// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VPass",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VPass", targets: ["VPassApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2")
    ],
    targets: [
        .executableTarget(
            name: "VPassApp",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .testTarget(
            name: "VPassAppTests",
            dependencies: ["VPassApp"]
        )
    ]
)
