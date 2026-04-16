// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AIPlanMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AIPlanMonitor",
            targets: ["AIPlanMonitor"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AIPlanMonitor",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "AIPlanMonitorTests",
            dependencies: ["AIPlanMonitor"]
        )
    ]
)
