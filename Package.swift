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
    targets: [
        .executableTarget(name: "VPassApp"),
        .testTarget(
            name: "VPassAppTests",
            dependencies: ["VPassApp"]
        )
    ]
)
