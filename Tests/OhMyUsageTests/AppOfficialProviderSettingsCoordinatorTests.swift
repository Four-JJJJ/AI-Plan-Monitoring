import XCTest
@testable import OhMyUsage

final class AppOfficialProviderSettingsCoordinatorTests: XCTestCase {
    func testUpdateOfficialQuotaDisplayModeRequestsPersistAndNotify() {
        var provider = ProviderDescriptor.defaultOfficialCodex()
        provider.enabled = false
        var providers = [provider]
        let coordinator = AppOfficialProviderSettingsCoordinator()

        let outcome = coordinator.updateOfficialProviderSettings(
            providerID: provider.id,
            sourceMode: .auto,
            webMode: .autoImport,
            quotaDisplayMode: .used,
            providers: &providers
        )

        XCTAssertEqual(providers[0].officialConfig?.quotaDisplayMode, .used)
        XCTAssertEqual(
            outcome,
            AppProviderSettingsMutationOutcome(
                shouldPersistAndRestart: true,
                shouldNotifyDisplayConfigChange: true
            )
        )
    }

    func testUpdateOfficialSourceAndWebModeWithoutDisplayChangeOnlyRequestsPersist() {
        var provider = ProviderDescriptor.defaultOfficialCodex()
        provider.enabled = false
        var providers = [provider]
        let coordinator = AppOfficialProviderSettingsCoordinator()

        let outcome = coordinator.updateOfficialProviderSettings(
            providerID: provider.id,
            sourceMode: .cli,
            webMode: .manual,
            quotaDisplayMode: .remaining,
            providers: &providers
        )

        XCTAssertEqual(providers[0].officialConfig?.sourceMode, .cli)
        XCTAssertEqual(providers[0].officialConfig?.webMode, .manual)
        XCTAssertEqual(
            outcome,
            AppProviderSettingsMutationOutcome(
                shouldPersistAndRestart: true,
                shouldNotifyDisplayConfigChange: false
            )
        )
    }

    func testUpdateTraeValueDisplayModeRequestsPersistAndNotify() {
        var provider = ProviderDescriptor.defaultOfficialTrae()
        provider.enabled = false
        var providers = [provider]
        let coordinator = AppOfficialProviderSettingsCoordinator()

        let outcome = coordinator.updateOfficialProviderSettings(
            providerID: provider.id,
            sourceMode: .auto,
            webMode: .disabled,
            quotaDisplayMode: .remaining,
            traeValueDisplayMode: .amount,
            providers: &providers
        )

        XCTAssertEqual(providers[0].officialConfig?.traeValueDisplayMode, .amount)
        XCTAssertEqual(
            outcome,
            AppProviderSettingsMutationOutcome(
                shouldPersistAndRestart: true,
                shouldNotifyDisplayConfigChange: true
            )
        )
    }
}
