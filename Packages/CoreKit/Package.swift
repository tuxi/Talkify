// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CoreKit",
    platforms: [
         .iOS(.v17),
         .macOS(.v15)
     ],
    products: [
        .library(
            name: "CoreKit",
            targets: ["CoreKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.6.0"),
        .package(url: "https://github.com/aliyun/alibabacloud-oss-swift-sdk-v2.git", from: "0.1.0-beta"),
    ],
    targets: [
        .target(
            name: "CoreKit",
            dependencies: [
                "Alamofire",
                .product(name: "AlibabaCloudOSS", package: "alibabacloud-oss-swift-sdk-v2"),
            ],
            path: "Sources/CoreKit"
        ),
        .testTarget(
            name: "CoreKitTests",
            dependencies: ["CoreKit"],
            path: "Tests/CoreKitTests"
        ),

    ]
)
