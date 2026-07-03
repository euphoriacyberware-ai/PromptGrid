// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PromptGridCore",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "PromptGridCore",
            targets: ["PromptGridCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/euphoriacyberware-ai/DrawThingsQueue", branch: "main"),
        .package(url: "https://github.com/euphoriacyberware-ai/DT-gRPC-Swift-Client", branch: "main"),
    ],
    targets: [
        .target(
            name: "PromptGridCore",
            dependencies: [
                .product(name: "DrawThingsQueue", package: "DrawThingsQueue"),
                .product(name: "DrawThingsClient", package: "DT-gRPC-Swift-Client"),
            ]
        ),
        .testTarget(
            name: "PromptGridCoreTests",
            dependencies: ["PromptGridCore"]
        ),
    ]
)
