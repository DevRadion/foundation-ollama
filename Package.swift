// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "foundation-ollama",
    platforms: [
        .macOS("27.0"),
        .macCatalyst("27.0"),
        .iOS("27.0"),
        .watchOS("27.0"),
        .visionOS("27.0"),
    ],
    products: [
        .library(
            name: "FoundationOllama",
            targets: ["FoundationOllama"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/mattt/ollama-swift.git", exact: "1.8.0"),
    ],
    targets: [
        .target(
            name: "FoundationOllama",
            dependencies: [
                .product(name: "Ollama", package: "ollama-swift"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "FoundationOllamaTests",
            dependencies: [
                "FoundationOllama",
                .product(name: "Ollama", package: "ollama-swift"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
