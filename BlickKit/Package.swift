// swift-tools-version: 5.10
// BlickKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import PackageDescription

let package = Package(
    name: "BlickKit",
    platforms: [
        .iOS("18.0"),
        .watchOS("11.6")
    ],
    products: [
        .library(name: "BlickKit", targets: ["BlickKit"])
    ],
    targets: [
        .target(name: "BlickKit"),
        .testTarget(name: "BlickKitTests", dependencies: ["BlickKit"])
    ]
)
