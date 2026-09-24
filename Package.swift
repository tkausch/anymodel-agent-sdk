// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "anymodel-swift-agent",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "AnyModelSwiftAgentSDK",
            targets: ["AnyModelSwiftAgentSDK"]
        ),
        .executable(
            name: "anymodel-swift-agent",
            targets: ["anymodel-swift-agent"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/huggingface/AnyLanguageModel", from: "0.13.0"),
    ],
    targets: [
        .target(
            name: "AnyModelSwiftAgentSDK",
            dependencies: [
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
            ]
        ),
        .executableTarget(
            name: "anymodel-swift-agent",
            dependencies: [
                "AnyModelSwiftAgentSDK",
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
            ]
        ),
        .testTarget(
            name: "AnyModelSwiftAgentTests",
            dependencies: [
                "AnyModelSwiftAgentSDK",
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
