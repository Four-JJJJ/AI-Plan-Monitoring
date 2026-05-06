import XCTest
@testable import AIPlanMonitor

final class SettingsDraftModelsTests: XCTestCase {
    func testRelayDraftSeedsGenericNewAPIDefaults() {
        let provider = ProviderDescriptor.makeOpenRelay(
            name: "Demo Relay",
            baseURL: "https://relay.example.com",
            preferredAdapterID: "generic-newapi"
        )

        let draft = RelaySettingsDraft(provider: provider)

        XCTAssertEqual(draft.providerID, provider.id)
        XCTAssertEqual(draft.name, "Demo Relay")
        XCTAssertEqual(draft.baseURL, "https://relay.example.com")
        XCTAssertEqual(draft.preferredAdapterID, "generic-newapi")
        XCTAssertFalse(draft.tokenUsageEnabled)
        XCTAssertTrue(draft.accountEnabled)
        XCTAssertEqual(draft.authHeader, "Authorization")
        XCTAssertEqual(draft.authScheme, "Bearer")
        XCTAssertEqual(draft.userIDHeader, "New-Api-User")
        XCTAssertEqual(draft.endpointPath, "/api/user/self")
        XCTAssertEqual(draft.remainingJSONPath, "div(data.quota,50000)")
        XCTAssertEqual(draft.unit, "USD")
    }

    func testOfficialDraftNormalizesUnsupportedModes() {
        var provider = ProviderDescriptor.defaultOfficialKiro()
        provider.officialConfig = OfficialProviderConfig(sourceMode: .web, webMode: .manual)

        let draft = OfficialSettingsDraft(provider: provider)

        XCTAssertEqual(draft.sourceMode, .auto)
        XCTAssertEqual(draft.webMode, .disabled)
        XCTAssertEqual(draft.quotaDisplayMode, .remaining)
    }
}
