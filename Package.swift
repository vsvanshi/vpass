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
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2"),
        .package(path: "Packages/VPassCore")
    ],
    targets: [
        .executableTarget(
            name: "VPassApp",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "VPassCore", package: "VPassCore")
            ]
        ),
        .testTarget(
            name: "VPassAppTests",
            dependencies: [
                "VPassApp",
                .product(name: "VPassCore", package: "VPassCore")
            ]
        )
    ]
)
