// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FileFlower",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "FileFlower",
            targets: ["FileFlower"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.60.0"),
    ],
    targets: [
        .target(
            name: "FileFlower",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        ),
    ]
)

