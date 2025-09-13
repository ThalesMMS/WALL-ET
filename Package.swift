// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WALL-ET",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        // Keep the main product out of SwiftPM test runs to avoid UIKit build on macOS.
        // You can reintroduce this when building the app via Xcode.
    ],
    dependencies: [
        // Bitcoin cryptography (C lib + Swift wrappers)
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", from: "0.15.0")
    ],
    targets: [
        // Logic-only core target (no UIKit), for pure SwiftPM testing
        .target(
            name: "CoreBitcoin",
            dependencies: [
                .product(name: "libsecp256k1", package: "secp256k1.swift")
            ],
            path: ".",
            sources: [
                "WALL-ET/Core/Bitcoin/MnemonicService.swift",
                "WALL-ET/Core/Bitcoin/BitcoinService.swift",
                "WALL-ET/Core/Bitcoin/CryptoService.swift",
                "WALL-ET/Core/Crypto/RIPEMD160.swift"
            ]
        ),
        // Removed the UI app target from SwiftPM context to enable pure logic tests
        .testTarget(
            name: "CoreBitcoinTests",
            dependencies: ["CoreBitcoin"],
            path: "WALL-ETTestsSPM"
        ),
        // Removed UI-bound test target from SwiftPM context
    ]
)
