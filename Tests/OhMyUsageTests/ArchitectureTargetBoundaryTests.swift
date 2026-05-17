import Foundation
import OhMyUsageApplication
import OhMyUsageBootstrap
import OhMyUsageDomain
import OhMyUsageFeatures
import OhMyUsagePresentation
import XCTest

final class ArchitectureTargetBoundaryTests: XCTestCase {
    func testNonExecutableTargetsKeepDependencyDirection() throws {
        let rules: [(directory: String, forbiddenImports: [String])] = [
            (
                "Sources/OhMyUsageDomain",
                ["OhMyUsage", "OhMyUsageApplication", "OhMyUsageInfrastructure", "OhMyUsageProviders", "OhMyUsagePresentation", "OhMyUsageFeatures", "OhMyUsageBootstrap", "SwiftUI", "AppKit", "Security", "LocalAuthentication"]
            ),
            (
                "Sources/OhMyUsageInfrastructure",
                ["OhMyUsage", "OhMyUsageApplication", "OhMyUsageProviders", "OhMyUsagePresentation", "OhMyUsageFeatures", "OhMyUsageBootstrap", "SwiftUI", "AppKit"]
            ),
            (
                "Sources/OhMyUsageProviders",
                ["OhMyUsage", "OhMyUsageApplication", "OhMyUsageInfrastructure", "OhMyUsagePresentation", "OhMyUsageFeatures", "OhMyUsageBootstrap", "SwiftUI", "AppKit"]
            ),
            (
                "Sources/OhMyUsageApplication",
                ["OhMyUsage", "OhMyUsageInfrastructure", "OhMyUsageProviders", "OhMyUsagePresentation", "OhMyUsageFeatures", "OhMyUsageBootstrap", "SwiftUI", "AppKit"]
            ),
            (
                "Sources/OhMyUsagePresentation",
                ["OhMyUsage", "OhMyUsageApplication", "OhMyUsageInfrastructure", "OhMyUsageProviders", "OhMyUsageFeatures", "OhMyUsageBootstrap", "AppKit"]
            ),
            (
                "Sources/OhMyUsageFeatures",
                ["OhMyUsage", "OhMyUsageBootstrap"]
            ),
            (
                "Sources/OhMyUsageBootstrap",
                ["OhMyUsage"]
            )
        ]

        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for rule in rules {
            let directoryURL = rootURL.appendingPathComponent(rule.directory)
            let sourceFiles = try swiftFiles(in: directoryURL)
            for sourceFile in sourceFiles {
                let source = try String(contentsOf: sourceFile, encoding: .utf8)
                let importedModules = importedModuleNames(in: source)
                for forbiddenImport in rule.forbiddenImports {
                    XCTAssertFalse(
                        importedModules.contains(forbiddenImport),
                        "\(sourceFile.path) should not import \(forbiddenImport)"
                    )
                }
            }
        }
    }

    func testPackageManifestKeepsNonExecutableTargetsOnAllowedLayerDependencies() throws {
        let targets = try packageManifestTargets()
        let expectedDependencies: [String: Set<String>] = [
            "OhMyUsageDomain": [],
            "OhMyUsageInfrastructure": ["OhMyUsageDomain"],
            "OhMyUsageProviders": ["OhMyUsageDomain"],
            "OhMyUsageApplication": ["OhMyUsageDomain"],
            "OhMyUsagePresentation": ["OhMyUsageDomain"],
            "OhMyUsageFeatures": ["OhMyUsageApplication", "OhMyUsagePresentation"],
            "OhMyUsageBootstrap": ["OhMyUsageApplication", "OhMyUsageFeatures", "OhMyUsagePresentation"]
        ]

        let nonExecutableTargets = targets.values.filter { $0.kind == .regular }
        XCTAssertEqual(
            Set(nonExecutableTargets.map(\.name)),
            Set(expectedDependencies.keys),
            "Package.swift should keep non-executable target boundaries explicit; update this guard when adding a layer target"
        )

        for (targetName, dependencies) in expectedDependencies {
            let target = try XCTUnwrap(
                targets[targetName],
                "Package.swift should declare a regular target named \(targetName)"
            )
            XCTAssertEqual(target.kind, .regular)
            XCTAssertEqual(
                target.dependencies,
                dependencies,
                "\(targetName) should keep the current one-way package dependency boundary"
            )
        }
    }

    func testPackageManifestPinsCurrentBroadExecutableAndTestDependencies() throws {
        let targets = try packageManifestTargets()
        let executableTarget = try XCTUnwrap(
            targets["OhMyUsage"],
            "Package.swift should declare the executable target"
        )
        let testTarget = try XCTUnwrap(
            targets["OhMyUsageTests"],
            "Package.swift should declare the test target"
        )
        let executableAllowedDependencies: Set<String> = [
            "OhMyUsageDomain",
            "OhMyUsageInfrastructure",
            "OhMyUsageProviders",
            "OhMyUsageApplication",
            "OhMyUsagePresentation",
            "OhMyUsageFeatures",
            "OhMyUsageBootstrap"
        ]
        let testAllowedDependencies = executableAllowedDependencies.union(["OhMyUsage"])

        XCTAssertEqual(executableTarget.kind, .executable)
        XCTAssertEqual(
            executableTarget.dependencies,
            executableAllowedDependencies,
            "TODO boundary guard: the executable target is still broadly wired. Do not widen it; when composition narrows, update this allowlist with the new boundary."
        )
        XCTAssertEqual(testTarget.kind, .test)
        XCTAssertEqual(
            testTarget.dependencies,
            testAllowedDependencies,
            "TODO boundary guard: the test target currently imports the full stack for architecture coverage. Do not widen it without documenting why."
        )
    }

    func testPackageNonExecutableTargetsDoNotImportUIFrameworks() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let targets = try packageManifestTargets()
        let forbiddenUIImports: Set<String> = ["SwiftUI", "AppKit"]

        for target in targets.values where target.kind == .regular {
            let directoryURL = rootURL.appendingPathComponent("Sources/\(target.name)")
            let sourceFiles = try swiftFiles(in: directoryURL)
            for sourceFile in sourceFiles {
                let source = try String(contentsOf: sourceFile, encoding: .utf8)
                let importedSpecifiers = importedImportSpecifiers(in: source)
                let forbiddenImports = forbiddenUIImports.intersection(importedSpecifiers)

                XCTAssertTrue(
                    forbiddenImports.isEmpty,
                    "\(sourceFile.path) is in non-executable target \(target.name) and should not import UI frameworks directly: \(forbiddenImports.sorted())"
                )
            }
        }
    }

    func testRuntimeDiagnosticsDarwinMachImportStaysExplicitlyAllowlisted() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let targets = try packageManifestTargets()
        let expectedExceptions: [String: Set<String>] = [
            "Sources/OhMyUsageApplication/RuntimeDiagnostics.swift": ["Darwin.Mach"]
        ]
        var observedExceptions: [String: Set<String>] = [:]

        for target in targets.values where target.kind == .regular {
            let directoryURL = rootURL.appendingPathComponent("Sources/\(target.name)")
            let sourceFiles = try swiftFiles(in: directoryURL)
            for sourceFile in sourceFiles {
                let source = try String(contentsOf: sourceFile, encoding: .utf8)
                let exceptionalImports = importedImportSpecifiers(in: source).intersection(["Darwin.Mach"])
                guard !exceptionalImports.isEmpty else {
                    continue
                }
                observedExceptions[relativePath(for: sourceFile, rootURL: rootURL)] = exceptionalImports
            }
        }

        XCTAssertEqual(
            observedExceptions,
            expectedExceptions,
            "RuntimeDiagnostics.swift may keep the current Darwin.Mach diagnostics import; add a focused allowlist entry before introducing another non-executable platform exception"
        )
    }

    func testBootstrapAndFeatureAssemblyExposePureUsageCompositionWithoutRuntimeIntegration() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let featureAssemblyURL = rootURL.appendingPathComponent("Sources/OhMyUsageFeatures/UsageFeatureAssembly.swift")
        let compositionRootURL = rootURL.appendingPathComponent("Sources/OhMyUsageBootstrap/OhMyUsageCompositionRoot.swift")
        let featureAssembly = try String(contentsOf: featureAssemblyURL, encoding: .utf8)
        let compositionRoot = try String(contentsOf: compositionRootURL, encoding: .utf8)

        let providerID = try XCTUnwrap(UsageProviderIdentity("codex"))
        let snapshot = UsageQuotaSnapshot(
            used: 32,
            limit: 80,
            capturedAtUnixSeconds: 1_700_000_000
        )
        let assembly = UsageFeatureAssembly()
        let descriptor = assembly.makeUsageFeatureDescriptor(
            providerID: providerID,
            title: "Codex",
            defaultForceRefresh: true
        )
        let request = assembly.makeRefreshRequest(for: descriptor)
        let summary = assembly.makeSummaryViewState(for: descriptor, snapshot: snapshot)
        let composition = OhMyUsageCompositionRoot(featureAssembly: assembly)
        let composedRequest = composition.makeUsageRefreshRequest(for: descriptor, forceRefresh: false)
        let composedSummary = composition.makeUsageSummaryViewState(for: descriptor, snapshot: snapshot)

        XCTAssertEqual(descriptor.providerID, providerID)
        XCTAssertEqual(descriptor.title, "Codex")
        XCTAssertTrue(descriptor.defaultForceRefresh)
        XCTAssertEqual(request.providerID, providerID)
        XCTAssertTrue(request.forceRefresh)
        XCTAssertEqual(summary.providerID, providerID)
        XCTAssertEqual(summary.title, "Codex")
        XCTAssertEqual(summary.usageRatio, 0.4)
        XCTAssertEqual(composedRequest.providerID, providerID)
        XCTAssertFalse(composedRequest.forceRefresh)
        XCTAssertEqual(composedSummary, summary)

        XCTAssertTrue(featureAssembly.contains("makeRefreshRequest"))
        XCTAssertTrue(featureAssembly.contains("makeSummaryViewState"))
        XCTAssertTrue(compositionRoot.contains("makeUsageRefreshRequest"))
        XCTAssertTrue(compositionRoot.contains("makeUsageSummaryViewState"))
        XCTAssertFalse(featureAssembly.contains("refreshUseCaseTypeName"))
        XCTAssertFalse(featureAssembly.contains("summaryViewStateTypeName"))

        for completeRuntimeResponsibility in [
            "AppViewModel",
            "StatusBarController",
            "SettingsWindowController",
            "NSApplication",
            "ProviderDescriptor",
            "makeApplication",
            "makeAppViewModel",
            "makeProvider",
            "startRuntime"
        ] {
            XCTAssertFalse(
                featureAssembly.contains(completeRuntimeResponsibility),
                "UsageFeatureAssembly should stay a pure value assembly boundary and must not claim complete runtime integration through \(completeRuntimeResponsibility)"
            )
            XCTAssertFalse(
                compositionRoot.contains(completeRuntimeResponsibility),
                "OhMyUsageCompositionRoot should stay a bootstrap composition boundary and must not claim complete runtime integration through \(completeRuntimeResponsibility)"
            )
        }
    }

    func testNonExecutableTargetsExposeExplicitResponsibilities() throws {
        let requiredResponsibilityFiles: [(directory: String, files: Set<String>)] = [
            (
                "Sources/OhMyUsageDomain",
                ["UsageProviderIdentity.swift", "UsageQuotaSnapshot.swift"]
            ),
            (
                "Sources/OhMyUsageInfrastructure",
                ["UsageCredentialStore.swift"]
            ),
            (
                "Sources/OhMyUsageProviders",
                ["UsageProviderFetching.swift"]
            ),
            (
                "Sources/OhMyUsageApplication",
                ["ProviderRefreshScheduler.swift", "RefreshUseCaseContracts.swift"]
            ),
            (
                "Sources/OhMyUsagePresentation",
                ["UsagePresentationModels.swift"]
            ),
            (
                "Sources/OhMyUsageFeatures",
                ["UsageFeatureAssembly.swift", "UsageFeatureDescriptor.swift"]
            ),
            (
                "Sources/OhMyUsageBootstrap",
                ["OhMyUsageCompositionRoot.swift"]
            )
        ]

        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for requirement in requiredResponsibilityFiles {
            let directoryURL = rootURL.appendingPathComponent(requirement.directory)
            let sourceFiles = try swiftFiles(in: directoryURL)
            let fileNames = Set(sourceFiles.map(\.lastPathComponent))
            let matchingFiles = fileNames.intersection(requirement.files)

            XCTAssertFalse(
                matchingFiles.isEmpty,
                "\(requirement.directory) should expose at least one explicit responsibility file, not only module markers"
            )

            let nonMarkerFiles = sourceFiles.filter { !isModuleMarkerFile($0) }
            XCTAssertFalse(
                nonMarkerFiles.isEmpty,
                "\(requirement.directory) should contain a compilable non-marker boundary type"
            )
        }
    }

    func testLayerBoundaryTypesAreImportableByArchitectureTests() throws {
        let providerID = try XCTUnwrap(UsageProviderIdentity("codex"))
        let snapshot = UsageQuotaSnapshot(
            used: 25,
            limit: 100,
            capturedAtUnixSeconds: 1_700_000_000
        )
        let request = UsageRefreshRequest(providerID: providerID, forceRefresh: true)
        let summary = UsageProviderSummaryViewState(
            providerID: providerID,
            title: "Codex",
            snapshot: snapshot
        )
        let featureAssembly = UsageFeatureAssembly()
        let compositionRoot = OhMyUsageCompositionRoot(featureAssembly: featureAssembly)

        XCTAssertEqual(request.providerID, providerID)
        XCTAssertEqual(snapshot.remaining, 75)
        XCTAssertEqual(summary.usageRatio, 0.25)
        XCTAssertEqual(
            compositionRoot.makeUsageSummaryViewState(providerID: providerID, title: "Codex", snapshot: snapshot),
            summary
        )
    }
}
