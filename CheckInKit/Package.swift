// swift-tools-version: 5.10
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import PackageDescription

let package = Package(
    name: "CheckInKit",
    platforms: [
        .iOS("17.6"),
        .watchOS("11.6")
    ],
    products: [
        .library(name: "CheckInKit", targets: ["CheckInKit"])
    ],
    targets: [
        .target(name: "CheckInKit"),
        .testTarget(name: "CheckInKitTests", dependencies: ["CheckInKit"])
    ]
)
