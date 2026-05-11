// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OhMyUsage",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "OhMyUsage",
            targets: ["OhMyUsage"]
        )
    ],
    targets: [
        .target(
            name: "OhMyUsageDomain"
        ),
        .target(
            name: "OhMyUsageInfrastructure",
            dependencies: ["OhMyUsageDomain"]
        ),
        .target(
            name: "OhMyUsageProviders",
            dependencies: [
                "OhMyUsageDomain",
                "OhMyUsageInfrastructure"
            ]
        ),
        .target(
            name: "OhMyUsageApplication",
            dependencies: [
                "OhMyUsageDomain",
                "OhMyUsageInfrastructure",
                "OhMyUsageProviders"
            ]
        ),
        .target(
            name: "OhMyUsagePresentation",
            dependencies: ["OhMyUsageDomain"]
        ),
        .target(
            name: "OhMyUsageFeatures",
            dependencies: [
                "OhMyUsageApplication",
                "OhMyUsagePresentation"
            ]
        ),
        .target(
            name: "OhMyUsageBootstrap",
            dependencies: [
                "OhMyUsageApplication",
                "OhMyUsageFeatures",
                "OhMyUsagePresentation"
            ]
        ),
        .executableTarget(
            name: "OhMyUsage",
            dependencies: [
                "OhMyUsageDomain",
                "OhMyUsageInfrastructure",
                "OhMyUsageProviders",
                "OhMyUsageApplication",
                "OhMyUsagePresentation",
                "OhMyUsageFeatures",
                "OhMyUsageBootstrap"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "OhMyUsageTests",
            dependencies: ["OhMyUsage"]
        )
    ]
)
