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
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "PortKiller",
            dependencies: ["HotKey"],
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PortKillerTests",
            dependencies: ["PortKiller"]
        )
    ]
)
