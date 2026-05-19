import Foundation
import OhMyUsageDomain

struct ProviderMetadata: Equatable {
    var presentation: ProviderPresentation
    var capabilities: ProviderCapabilities
    var settingsSpec: ProviderSettingsSpec
    var preferredMetricCount: Int
}

enum ProviderMetadataCatalog {
    static func metadata(for provider: ProviderDescriptor) -> ProviderMetadata {
        ProviderMetadata(
            presentation: presentation(for: provider),
            capabilities: capabilities(for: provider),
            settingsSpec: settingsSpec(for: provider),
            preferredMetricCount: preferredMetricCount(for: provider)
        )
    }

    static func presentation(for provider: ProviderDescriptor?) -> ProviderPresentation {
        ProviderPresentationMetadataCatalog.presentation(for: provider)
    }

    static func capabilities(for provider: ProviderDescriptor) -> ProviderCapabilities {
        ProviderCapabilityMetadataCatalog.capabilities(for: provider)
    }

    static func settingsSpec(for provider: ProviderDescriptor) -> ProviderSettingsSpec {
        ProviderSettingsMetadataCatalog.settingsSpec(for: provider)
    }

    static func preferredMetricCount(for provider: ProviderDescriptor) -> Int {
        ProviderTypeMetadataCatalog.metadata(for: provider.type).preferredMetricCount
    }

    static func supportedOfficialSourceModes(for provider: ProviderDescriptor) -> [OfficialSourceMode] {
        ProviderSettingsMetadataCatalog.supportedOfficialSourceModes(for: provider)
    }

    static func supportedOfficialWebModes(for provider: ProviderDescriptor) -> [OfficialWebMode] {
        ProviderSettingsMetadataCatalog.supportedOfficialWebModes(for: provider)
    }

    static func supportsOfficialBearerCredentialInput(for provider: ProviderDescriptor) -> Bool {
        ProviderSettingsMetadataCatalog.supportsOfficialBearerCredentialInput(for: provider)
    }

}
