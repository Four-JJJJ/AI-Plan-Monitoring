import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

@MainActor
final class LocalProviderDiscoveryCoordinatorTests: XCTestCase {
    func testNoCandidatesReturnsNothingFound() async {
        let coordinator = LocalProviderDiscoveryCoordinator()

        let result = await coordinator.discoverLocalProviders(
            candidates: [],
            makeProvider: { _ in fatalError("unused") },
            handleFetchedSnapshot: { _, _ in XCTFail("unused") },
            clearProviderError: { _ in },
            clearProviderFailures: { _ in },
            markLastUpdatedAt: { _ in },
            setProviderEnabled: { _ in },
            normalizeStatusBarSelections: {},
            persistConfiguration: { true },
            restartPolling: {},
            notifyStatusBarDisplayConfigChanged: {},
            displayNameForDiscovery: { _ in "" },
            nothingFoundText: "nothing",
            language: .en
        )

        XCTAssertEqual(result, "nothing")
    }

    func testSuccessfulDiscoveryCommitsSnapshotsAndReturnsFoundBody() async {
        let coordinator = LocalProviderDiscoveryCoordinator()
        var provider = ProviderDescriptor.defaultOfficialCodex()
        provider.enabled = false
        var handledProviders: [String] = []
        var enabledProviders: [String] = []
        var notified = false
        var restarted = false
        var normalized = false
        var persisted = false

        let result = await coordinator.discoverLocalProviders(
            candidates: [provider],
            makeProvider: { descriptor in
                LocalDiscoverySuccessProvider(
                    descriptor: descriptor,
                    snapshot: UsageSnapshot(
                        source: descriptor.id,
                        status: .ok,
                        remaining: 80,
                        used: 20,
                        limit: 100,
                        unit: "%",
                        updatedAt: Date(),
                        note: "ok",
                        sourceLabel: "Official"
                    )
                )
            },
            handleFetchedSnapshot: { descriptor, _ in handledProviders.append(descriptor.id) },
            clearProviderError: { _ in },
            clearProviderFailures: { _ in },
            markLastUpdatedAt: { _ in },
            setProviderEnabled: { enabledProviders.append($0) },
            normalizeStatusBarSelections: { normalized = true },
            persistConfiguration: {
                persisted = true
                return true
            },
            restartPolling: { restarted = true },
            notifyStatusBarDisplayConfigChanged: { notified = true },
            displayNameForDiscovery: { _ in "Codex" },
            nothingFoundText: "nothing",
            language: .en
        )

        XCTAssertEqual(handledProviders, [provider.id])
        XCTAssertEqual(enabledProviders, [provider.id])
        XCTAssertTrue(normalized)
        XCTAssertTrue(persisted)
        XCTAssertTrue(restarted)
        XCTAssertTrue(notified)
        XCTAssertTrue(result.contains("Codex"))
    }
}

private struct LocalDiscoverySuccessProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    let snapshot: UsageSnapshot

    func fetch() async throws -> UsageSnapshot {
        snapshot
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        snapshot
    }
}
