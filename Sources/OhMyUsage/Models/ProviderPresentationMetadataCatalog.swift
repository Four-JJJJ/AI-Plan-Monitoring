import Foundation
import OhMyUsageDomain

enum ProviderPresentationMetadataCatalog {
    static func presentation(for provider: ProviderDescriptor?) -> ProviderPresentation {
        ProviderPresentation(
            displayName: displayName(for: provider),
            iconName: iconName(for: provider),
            fallbackSystemIcon: fallbackIcon(for: provider)
        )
    }

    private static func displayName(for provider: ProviderDescriptor?) -> String {
        guard let provider else { return "第三方中转站" }
        if provider.isRelay {
            if provider.isOfficialRelayProvider,
               let adapterID = provider.officialRelayAdapterID,
               let displayName = OfficialRelayMetadataCatalog.metadata(forAdapterID: adapterID)?.displayName {
                return displayName
            }
            return provider.name
        }
        let type = typeMetadata(for: provider.type)
        return provider.family == .official ? (type.officialDisplayName ?? type.displayName) : type.displayName
    }

    private static func iconName(for provider: ProviderDescriptor?) -> String {
        guard let provider else { return "menu_relay_icon" }
        if provider.isRelay {
            if provider.isOfficialRelayProvider,
               let adapterID = provider.officialRelayAdapterID,
               let iconName = OfficialRelayMetadataCatalog.metadata(forAdapterID: adapterID)?.iconName {
                return iconName
            }
            return RelayIconMetadataCatalog.iconOverrideName(for: provider) ?? "menu_relay_icon"
        }
        return typeMetadata(for: provider.type).iconName
    }

    private static func fallbackIcon(for provider: ProviderDescriptor?) -> String {
        guard let provider else { return "link" }
        return typeMetadata(for: provider.type).fallbackSystemIcon
    }

    private static func typeMetadata(for type: ProviderType) -> ProviderTypeMetadata {
        ProviderTypeMetadataCatalog.metadata(for: type)
    }
}
