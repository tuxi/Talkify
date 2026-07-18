// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FeatureAuth",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "FeatureAuth",
            targets: ["FeatureAuth"]
        ),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../DesignKit")
    ],
    targets: [
        .target(
            name: "FeatureAuth",
            dependencies: [
                "CoreKit",
                "DesignKit",
            ],
        ),
    ]
)
