// swift-tools-version: 6.4
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
    .strictMemorySafety(),
]

let package = Package(
    name: "PortKiller",
    platforms: [.macOS(.v27)],
    products: [
        .executable(name: "PortKiller", targets: ["PortKiller"]),
        .library(name: "PortKillerKit", targets: ["PortKillerKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.1.5"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(
            name: "PortKillerKit",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "OrderedCollections", package: "swift-collections"),
            ],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "PortKiller",
            dependencies: [
                "PortKillerKit",
                .product(name: "DequeModule", package: "swift-collections"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: swiftSettings + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "PortKillerKitTests",
            dependencies: ["PortKillerKit"],
            swiftSettings: swiftSettings
        ),
    ]
)
