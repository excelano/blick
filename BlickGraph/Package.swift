// swift-tools-version: 5.10
// BlickGraph
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import PackageDescription

let package = Package(
    name: "BlickGraph",
    platforms: [
        .iOS("18.0")
    ],
    products: [
        .library(name: "BlickGraph", targets: ["BlickGraph"])
    ],
    dependencies: [
        .package(path: "../BlickKit"),
        .package(
            url: "https://github.com/AzureAD/microsoft-authentication-library-for-objc",
            from: "2.11.0"
        )
    ],
    targets: [
        .target(
            name: "BlickGraph",
            dependencies: [
                "BlickKit",
                .product(name: "MSAL", package: "microsoft-authentication-library-for-objc")
            ]
        ),
        .testTarget(
            name: "BlickGraphTests",
            dependencies: ["BlickGraph"]
        )
    ]
)
