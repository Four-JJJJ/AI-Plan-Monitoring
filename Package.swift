// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AIBalanceMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AIBalanceMonitor",
            targets: ["AIBalanceMonitor"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AIBalanceMonitor",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "AIBalanceMonitorTests",
            dependencies: ["AIBalanceMonitor"]
        )
    ]
)
