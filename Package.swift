// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Ping",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
    ],
    products: [
        .library(
            name: "PingShared",
            targets: ["PingShared"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.36.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "PingShared",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Shared"
        ),
        .testTarget(
            name: "PingSharedTests",
            dependencies: [
                "PingShared",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Tests/PingSharedTests"
        ),
    ]
)
