import XCTest
import OhMyUsageProviders
@testable import OhMyUsage

final class ProviderFactoryTests: XCTestCase {
    func testFactoryMapsRepresentativeProviderTypes() {
        let factory = ProviderFactory(keychain: makeTestKeychain())

        XCTAssertTrue(factory.makeProvider(for: .defaultOfficialCodex()) is CodexProvider)
        XCTAssertTrue(factory.makeProvider(for: .defaultOfficialClaude()) is ClaudeProvider)
        XCTAssertTrue(factory.makeProvider(for: .defaultOfficialTrae()) is TraeProvider)
        XCTAssertTrue(factory.makeProvider(for: .defaultOfficialOpenRouterAPI()) is OpenRouterProvider)
        XCTAssertTrue(factory.makeProvider(for: .defaultOpenAilinyu()) is RelayProvider)
        XCTAssertTrue(factory.makeProvider(for: .defaultOfficialKimi()) is KimiSmartProvider)
    }

    func testTraeProviderUsesInjectedBrowserCredentialService() throws {
        let browserCredentialService = BrowserCredentialService(
            bearerCandidatesOverride: { _ in [] },
            cacheTTL: 0
        )
        let factory = ProviderFactory(
            keychain: makeTestKeychain(),
            browserCredentialService: browserCredentialService
        )

        let provider = try XCTUnwrap(factory.makeProvider(for: ProviderDescriptor.defaultOfficialTrae()) as? TraeProvider)
        XCTAssertTrue(provider.browserCredentialService === browserCredentialService)
    }

    func testDefaultRegistryRegistersEveryProviderType() {
        let registry = ProviderFactoryRegistry()

        XCTAssertEqual(registry.registeredProviderTypes, Set(ProviderType.allCases))
    }

    func testFactoryCanExposeProviderFetchingAdapter() async throws {
        let descriptor = ProviderDescriptor(
            id: "test-provider",
            name: "Test Provider",
            type: .gemini,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 3, notifyOnAuthError: true),
            auth: .none
        )
        let factory = ProviderFactory(
            keychain: makeTestKeychain(),
            registry: ProviderFactoryRegistry(makers: Dictionary(
                uniqueKeysWithValues: ProviderType.allCases.map { type in
                    (type, { descriptor, _ in
                    StubUsageProvider(
                        descriptor: descriptor,
                        snapshot: UsageSnapshot(
                            source: descriptor.id,
                            status: .ok,
                            remaining: 30,
                            used: 70,
                            limit: 100,
                            unit: "tokens",
                            updatedAt: Date(timeIntervalSince1970: 123),
                            note: "ok"
                        )
                    )
                    } as ProviderFactoryRegistry.Maker)
                }
            ))
        )

        let fetcher = factory.makeProviderFetcher(for: descriptor)
        let snapshot = try await fetcher.fetchUsageSnapshot(forceRefresh: true)

        XCTAssertEqual(fetcher.providerID.rawValue, "test-provider")
        XCTAssertEqual(snapshot.used, 70)
        XCTAssertEqual(snapshot.limit, 100)
        XCTAssertEqual(snapshot.capturedAtUnixSeconds, 123)
    }
}

private struct StubUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    let snapshot: UsageSnapshot

    func fetch() async throws -> UsageSnapshot {
        snapshot
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        snapshot
    }
}
