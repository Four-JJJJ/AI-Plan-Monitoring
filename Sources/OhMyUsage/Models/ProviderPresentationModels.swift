import Foundation

struct ProviderCapabilities: Equatable, Sendable {
    var supportsBalance: Bool
    var supportsQuotaWindows: Bool
    var supportsAccountSwitching: Bool
    var supportsLocalUsageHistory: Bool
    var usesPercentageMenuCard: Bool

    static func capabilities(for provider: ProviderDescriptor) -> ProviderCapabilities {
        ProviderMetadataCatalog.capabilities(for: provider)
    }
}

struct ProviderPresentation: Equatable, Sendable {
    var displayName: String
    var iconName: String
    var fallbackSystemIcon: String
}
