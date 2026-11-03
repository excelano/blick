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
    dependencies: [
        .package(url: "https://github.com/excelano/bogenzeit-swift", .upToNextMinor(from: "0.2.0"))
    ],
    targets: [
        .target(name: "BlickKit", dependencies: [
            .product(name: "Bogenzeit", package: "bogenzeit-swift"),
            .product(name: "BogenzeitUI", package: "bogenzeit-swift")
        ]),
        .testTarget(name: "BlickKitTests", dependencies: ["BlickKit"])
    ]
)
