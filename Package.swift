// swift-tools-version:3.1

import PackageDescription

let package = Package(
    name: "SwiftBeaker",
    dependencies: [.Package(url: "https://github.com/ikesyo/Himotoki", majorVersion: 3),
                   .Package(url: "https://github.com/kylef/Stencil", majorVersion: 0),
                   .Package(url: "https://github.com/kylef/Commander", majorVersion: 0)
    ]
)
