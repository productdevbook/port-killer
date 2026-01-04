// swift-tools-version: 6.0
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
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", from: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "PortKiller",
            dependencies: [
                "KeyboardShortcuts",
                "Defaults",
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern")
            ],
            path: "Sources",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                // Link Rust backend library
                // Build with: ./scripts/build-rust.sh
                .unsafeFlags(["-L.build/rust/lib", "-lportkiller"])
            ]
        ),
        .testTarget(
            name: "PortKillerTests",
            dependencies: ["PortKiller"],
            path: "Tests"
        )
    ]
)
