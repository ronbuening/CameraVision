// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CameraVision",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "AISidecarCore",
            targets: ["AISidecarCore"]
        ),
        .executable(
            name: "aisidecar",
            targets: ["AISidecarCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "AISidecarCore",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "AISidecarCLI",
            dependencies: [
                "AISidecarCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "AISidecarCoreTests",
            dependencies: ["AISidecarCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
