// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WALL-ET",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "WALL-ET",
            targets: ["WALL-ET"]
        )
    ],
    dependencies: [
        // Bitcoin cryptography (C lib + Swift wrappers)
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", from: "0.15.0")
    ],
    targets: [
        .target(
            name: "WALL-ET",
            dependencies: [
                .product(name: "libsecp256k1", package: "secp256k1.swift")
            ],
            path: "WALL-ET"
        ),
        .testTarget(
            name: "WALL-ETTests",
            dependencies: ["WALL-ET"],
            path: "WALL-ETTests"
        )
    ]
)
