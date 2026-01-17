// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Control",
    platforms: [
        .macOS(.v12)  // macOS 12.0+ (Monterey and later)
    ],
    products: [
        .executable(name: "control", targets: ["Control"]),
        .library(name: "ControlKit", targets: ["ControlKit"])
    ],
    dependencies: [
        // CLI argument parsing
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        // TOML configuration parsing
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
        // Structured logging
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0")
    ],
    targets: [
        // Main executable target
        .executableTarget(
            name: "Control",
            dependencies: [
                "ControlKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "TOMLKit", package: "TOMLKit"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/Control"
        ),
        // Reusable framework for core functionality
        .target(
            name: "ControlKit",
            dependencies: [
                .product(name: "TOMLKit", package: "TOMLKit"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/ControlKit"
        ),
        // Unit tests
        .testTarget(
            name: "ControlTests",
            dependencies: ["Control", "ControlKit"],
            path: "Tests/Unit"
        ),
        // Integration tests
        .testTarget(
            name: "ControlIntegrationTests",
            dependencies: ["Control", "ControlKit"],
            path: "Tests/Integration"
        )
    ]
)
