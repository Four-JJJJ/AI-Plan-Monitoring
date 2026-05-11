import Foundation

struct ProviderDefinition: Equatable {
    var id: String
    var type: ProviderType
    var family: ProviderFamily
    var displayName: String
    var iconName: String
    var fallbackSystemIcon: String
    var capabilities: ProviderCapabilities
    var settingsSpec: ProviderSettingsSpec
    var preferredMetricCount: Int

    var supportsAccountSwitch: Bool {
        capabilities.supportsAccountSwitching
    }

    var supportsHistory: Bool {
        capabilities.supportsLocalUsageHistory
    }
}

enum ProviderDefinitionRegistry {
    static func definition(for provider: ProviderDescriptor) -> ProviderDefinition {
        let presentation = ProviderPresentationRegistry.presentation(for: provider)
        return ProviderDefinition(
            id: provider.id,
            type: provider.type,
            family: provider.family,
            displayName: presentation.displayName,
            iconName: presentation.iconName,
            fallbackSystemIcon: presentation.fallbackSystemIcon,
            capabilities: ProviderCapabilities.capabilities(for: provider),
            settingsSpec: ProviderSettingsSpec.resolve(for: provider),
            preferredMetricCount: QuotaMetricDisplayFactory.preferredMetricCount(for: provider)
        )
    }

    static func definitions(for providers: [ProviderDescriptor]) -> [ProviderDefinition] {
        providers.map(definition)
    }
}
