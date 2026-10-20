// swift-tools-version: 5.10
// BlickGraph
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import PackageDescription

let package = Package(
    name: "BlickGraph",
    platforms: [
        .iOS("18.0"),
        .watchOS("11.6")
    ],
    products: [
        .library(name: "BlickGraph", targets: ["BlickGraph"])
    ],
    dependencies: [
        .package(path: "../BlickKit")
    ],
    targets: [
        .target(
            name: "BlickGraph",
            dependencies: ["BlickKit"]
        ),
        .testTarget(
            name: "BlickGraphTests",
            dependencies: ["BlickGraph"]
        )
    ]
)
