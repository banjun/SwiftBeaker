// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "SwiftBeaker",
    products: [.executable(name: "SwiftBeaker", targets: ["SwiftBeaker"])],
    dependencies: [.package(url: "https://github.com/ikesyo/Himotoki", from: "3.0.0"),
                   .package(url: "https://github.com/kylef/Stencil", from: "0.0.0"),
                   .package(url: "https://github.com/kylef/Commander", from: "0.0.0")
    ],
    targets: [
        .target(name: "SwiftBeaker",
                dependencies: ["Himotoki", "Stencil", "Commander"],
                path: "Sources")
    ]
)
