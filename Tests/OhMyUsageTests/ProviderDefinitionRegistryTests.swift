import XCTest
@testable import OhMyUsage

final class ProviderDefinitionRegistryTests: XCTestCase {
    func testOfficialCodexDefinitionAggregatesPresentationCapabilitiesAndSettings() {
        let definition = ProviderDefinitionRegistry.definition(for: ProviderDescriptor.defaultOfficialCodex())

        XCTAssertEqual(definition.id, "codex-official")
        XCTAssertEqual(definition.type, .codex)
        XCTAssertEqual(definition.family, .official)
        XCTAssertEqual(definition.displayName, "Codex")
        XCTAssertEqual(definition.iconName, "menu_codex_icon")
        XCTAssertEqual(definition.fallbackSystemIcon, "terminal.fill")
        XCTAssertTrue(definition.supportsAccountSwitch)
        XCTAssertTrue(definition.supportsHistory)
        XCTAssertTrue(definition.capabilities.usesPercentageMenuCard)
        XCTAssertEqual(definition.settingsSpec.supportedSourceModes, [.auto, .api, .cli, .web])
        XCTAssertEqual(definition.preferredMetricCount, 2)
    }

    func testClaudeDefinitionUsesFourMetricsAndManualCookieSettings() {
        let definition = ProviderDefinitionRegistry.definition(for: ProviderDescriptor.defaultOfficialClaude())

        XCTAssertEqual(definition.displayName, "Claude")
        XCTAssertEqual(definition.preferredMetricCount, 4)
        XCTAssertEqual(definition.settingsSpec.credentialFields.map(\.kind), [.manualCookie])
        XCTAssertTrue(definition.capabilities.supportsQuotaWindows)
    }

    func testRelayDefinitionUsesResolvedProviderPresentationAndCapabilities() {
        let provider = ProviderDescriptor.makeOpenRelay(
            name: "Relay X",
            baseURL: "https://relay.example.com"
        )
        let definition = ProviderDefinitionRegistry.definition(for: provider)

        XCTAssertEqual(definition.displayName, "Relay X")
        XCTAssertEqual(definition.iconName, "menu_relay_icon")
        XCTAssertEqual(definition.fallbackSystemIcon, "link")
        XCTAssertTrue(definition.capabilities.supportsBalance)
        XCTAssertFalse(definition.capabilities.usesPercentageMenuCard)
        XCTAssertTrue(definition.settingsSpec.credentialFields.isEmpty)
    }

    func testDefinitionsPreserveProviderOrder() {
        let providers = [
            ProviderDescriptor.defaultOfficialCodex(),
            ProviderDescriptor.defaultOfficialClaude(),
            ProviderDescriptor.makeOpenRelay(name: "Relay X", baseURL: "https://relay.example.com")
        ]

        XCTAssertEqual(
            ProviderDefinitionRegistry.definitions(for: providers).map(\.id),
            providers.map(\.id)
        )
    }
}
