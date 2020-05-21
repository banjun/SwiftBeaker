// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftBeaker",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.0.5"),
        .package(url: "https://github.com/kylef/Stencil", from: "0.13.0"),
    ],
    targets: [
        .target(
            name: "SwiftBeaker",
            dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser"), "SwiftBeakerCore"],
            path: "SwiftBeaker"),
        .target(
            name: "SwiftBeakerCore",
            dependencies: ["Stencil"],
            path: "Sources"),
        .testTarget(
            name: "SwiftBeakerTests",
            dependencies: ["SwiftBeaker", "SwiftBeakerCore"]),
    ]
)
