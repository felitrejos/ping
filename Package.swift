// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Mako",
    platforms: [
        .macOS("15.0"),
        .iOS("18.0"),
    ],
    products: [
        .library(
            name: "MakoShared",
            targets: ["MakoShared"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.36.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "MakoShared",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: ".",
            sources: ["Shared"]
        ),
        .testTarget(
            name: "MakoSharedTests",
            dependencies: [
                "MakoShared",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Tests/MakoSharedTests"
        ),
    ]
)
