import Foundation
import OhMyUsageDomain

struct ProviderDefinition: Equatable {
    var id: String
    var type: ProviderType
    var family: ProviderFamily
    var presentation: ProviderPresentation
    var capabilities: ProviderCapabilities
    var settingsSpec: ProviderSettingsSpec
    var preferredMetricCount: Int

    var displayName: String {
        presentation.displayName
    }

    var iconName: String {
        presentation.iconName
    }

    var fallbackSystemIcon: String {
        presentation.fallbackSystemIcon
    }

    var supportsAccountSwitch: Bool {
        capabilities.supportsAccountSwitching
    }

    var supportsHistory: Bool {
        capabilities.supportsLocalUsageHistory
    }
}

enum ProviderDefinitionRegistry {
    static var defaultDefinitions: [ProviderDefinition] {
        definitions(for: AppConfig.default.providers)
    }

    static func metadata(for provider: ProviderDescriptor) -> ProviderMetadata {
        ProviderMetadataCatalog.metadata(for: provider)
    }

    static func presentation(for provider: ProviderDescriptor) -> ProviderPresentation {
        metadata(for: provider).presentation
    }

    static func presentation(for provider: ProviderDescriptor?) -> ProviderPresentation {
        guard let provider else {
            return ProviderMetadataCatalog.presentation(for: nil)
        }
        return presentation(for: provider)
    }

    static func capabilities(for provider: ProviderDescriptor) -> ProviderCapabilities {
        metadata(for: provider).capabilities
    }

    static func settingsSpec(for provider: ProviderDescriptor) -> ProviderSettingsSpec {
        metadata(for: provider).settingsSpec
    }

    static func preferredMetricCount(for provider: ProviderDescriptor) -> Int {
        metadata(for: provider).preferredMetricCount
    }

    static func definition(for provider: ProviderDescriptor) -> ProviderDefinition {
        let metadata = metadata(for: provider)
        return definition(for: provider, metadata: metadata)
    }

    static func definitions(for providers: [ProviderDescriptor]) -> [ProviderDefinition] {
        providers.map(definition)
    }

    private static func definition(for provider: ProviderDescriptor, metadata: ProviderMetadata) -> ProviderDefinition {
        return ProviderDefinition(
            id: provider.id,
            type: provider.type,
            family: provider.family,
            presentation: metadata.presentation,
            capabilities: metadata.capabilities,
            settingsSpec: metadata.settingsSpec,
            preferredMetricCount: metadata.preferredMetricCount
        )
    }
}
