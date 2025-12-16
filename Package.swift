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
    targets: [
        .executableTarget(
            name: "PortKiller",
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
