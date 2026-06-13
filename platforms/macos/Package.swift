// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PortKiller",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "PortKiller", targets: ["PortKiller"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
        .package(url: "https://github.com/sindresorhus/Defaults", from: "9.0.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", from: "1.1.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1")
    ],
    targets: [
        .executableTarget(
            name: "PortKiller",
            dependencies: [
                "KeyboardShortcuts",
                "Defaults",
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                // Swift 6.2 performance optimizations
                .enableExperimentalFeature("NonisolatedNonsendingByDefault"),
                .enableExperimentalFeature("InlineArrayTypeSugar"),
                // Default MainActor isolation - reduces boilerplate, prevents actor hops
                .enableUpcomingFeature("DefaultIsolationMainActor"),
                // Enable Span types for zero-copy memory access (Swift 6.2+)
                .enableExperimentalFeature("LifetimeDependence"),
                .enableExperimentalFeature("Span")
            ]
        ),
        .testTarget(
            name: "PortKillerTests",
            dependencies: ["PortKiller"],
            path: "Tests"
        )
    ]
)
