import Foundation
import OhMyUsageDomain

enum ProviderCapabilityMetadataCatalog {
    static func capabilities(for provider: ProviderDescriptor) -> ProviderCapabilities {
        let type = ProviderTypeMetadataCatalog.metadata(for: provider.type)
        return ProviderCapabilities(
            supportsBalance: provider.isRelay || provider.family == .thirdParty || provider.type == .openrouterCredits,
            supportsQuotaWindows: provider.family == .official || provider.relayDisplayMode == .quotaPercent,
            supportsAccountSwitching: provider.family == .official && type.supportsAccountSwitching,
            supportsLocalUsageHistory: provider.family == .official && type.supportsLocalUsageHistory,
            usesPercentageMenuCard: provider.family == .official || provider.type == .kimi || provider.relayDisplayMode == .quotaPercent
        )
    }
}
