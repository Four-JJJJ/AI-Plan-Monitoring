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
        .target(
            name: "AIPlanMonitorDomain"
        ),
        .target(
            name: "AIPlanMonitorInfrastructure",
            dependencies: ["AIPlanMonitorDomain"]
        ),
        .target(
            name: "AIPlanMonitorProviders",
            dependencies: [
                "AIPlanMonitorDomain",
                "AIPlanMonitorInfrastructure"
            ]
        ),
        .target(
            name: "AIPlanMonitorApplication",
            dependencies: [
                "AIPlanMonitorDomain",
                "AIPlanMonitorInfrastructure",
                "AIPlanMonitorProviders"
            ]
        ),
        .target(
            name: "AIPlanMonitorPresentation",
            dependencies: ["AIPlanMonitorDomain"]
        ),
        .target(
            name: "AIPlanMonitorFeatures",
            dependencies: [
                "AIPlanMonitorApplication",
                "AIPlanMonitorPresentation"
            ]
        ),
        .target(
            name: "AIPlanMonitorBootstrap",
            dependencies: [
                "AIPlanMonitorApplication",
                "AIPlanMonitorFeatures",
                "AIPlanMonitorPresentation"
            ]
        ),
        .executableTarget(
            name: "AIPlanMonitor",
            dependencies: [
                "AIPlanMonitorDomain",
                "AIPlanMonitorInfrastructure",
                "AIPlanMonitorProviders",
                "AIPlanMonitorApplication",
                "AIPlanMonitorPresentation",
                "AIPlanMonitorFeatures",
                "AIPlanMonitorBootstrap"
            ],
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
