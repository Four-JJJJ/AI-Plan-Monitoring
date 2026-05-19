import Foundation
import OhMyUsageDomain

struct AppProviderSettingsMutationOutcome: Equatable {
    var shouldPersistAndRestart: Bool = false
    var shouldNotifyDisplayConfigChange: Bool = false

    static let none = AppProviderSettingsMutationOutcome()
}

struct AppOfficialProviderSettingsCoordinator {
    func updateOfficialProviderSettings(
        providerID: String,
        sourceMode: OfficialSourceMode,
        webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode? = nil,
        traeValueDisplayMode: OfficialTraeValueDisplayMode? = nil,
        providers: inout [ProviderDescriptor]
    ) -> AppProviderSettingsMutationOutcome {
        guard let idx = providers.firstIndex(where: { $0.id == providerID }),
              providers[idx].family == .official else {
            return .none
        }

        var provider = providers[idx]
        let previousDisplaysUsedQuota = provider.displaysUsedQuota
        let previousTraeDisplaysAmount = provider.traeDisplaysAmount
        var official = provider.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type)
        official.sourceMode = sourceMode
        official.webMode = webMode
        if let quotaDisplayMode {
            official.quotaDisplayMode = quotaDisplayMode
        }
        if let traeValueDisplayMode {
            official.traeValueDisplayMode = traeValueDisplayMode
        }
        provider.officialConfig = official
        providers[idx] = provider

        return AppProviderSettingsMutationOutcome(
            shouldPersistAndRestart: true,
            shouldNotifyDisplayConfigChange: previousDisplaysUsedQuota != provider.displaysUsedQuota
                || previousTraeDisplaysAmount != provider.traeDisplaysAmount
        )
    }
}
