// swift-tools-version: 5.10
// CheckInGraph
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import PackageDescription

let package = Package(
    name: "CheckInGraph",
    platforms: [
        .iOS("17.6")
    ],
    products: [
        .library(name: "CheckInGraph", targets: ["CheckInGraph"])
    ],
    dependencies: [
        .package(path: "../CheckInKit"),
        .package(
            url: "https://github.com/AzureAD/microsoft-authentication-library-for-objc",
            from: "2.11.0"
        )
    ],
    targets: [
        .target(
            name: "CheckInGraph",
            dependencies: [
                "CheckInKit",
                .product(name: "MSAL", package: "microsoft-authentication-library-for-objc")
            ]
        ),
        .testTarget(
            name: "CheckInGraphTests",
            dependencies: ["CheckInGraph"]
        )
    ]
)
