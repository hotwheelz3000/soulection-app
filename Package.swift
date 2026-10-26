// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SoulectionRadio",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "SoulectionRadio",
            targets: ["SoulectionRadio"]
        ),
    ],
    targets: [
        .target(
            name: "SoulectionRadio"
        ),
    ]
)
