import Foundation

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
        ProviderPresentation(
            displayName: displayName(for: provider),
            iconName: iconName(for: provider),
            fallbackSystemIcon: fallbackIcon(for: provider)
        )
    }

    static func capabilities(for provider: ProviderDescriptor) -> ProviderCapabilities {
        let type = typeMetadata(for: provider.type)
        return ProviderCapabilities(
            supportsBalance: provider.isRelay || provider.family == .thirdParty || provider.type == .openrouterCredits,
            supportsQuotaWindows: provider.family == .official || provider.relayDisplayMode == .quotaPercent,
            supportsAccountSwitching: provider.family == .official && type.supportsAccountSwitching,
            supportsLocalUsageHistory: provider.family == .official && type.supportsLocalUsageHistory,
            usesPercentageMenuCard: provider.family == .official || provider.type == .kimi || provider.relayDisplayMode == .quotaPercent
        )
    }

    static func settingsSpec(for provider: ProviderDescriptor) -> ProviderSettingsSpec {
        ProviderSettingsSpec(
            providerType: provider.type,
            supportedSourceModes: supportedOfficialSourceModes(for: provider),
            supportedWebModes: supportedOfficialWebModes(for: provider),
            credentialFields: credentialFields(for: provider),
            showsQuotaDisplayPreference: provider.family == .official,
            showsTraeValueDisplayMode: provider.type == .trae
        )
    }

    static func preferredMetricCount(for provider: ProviderDescriptor) -> Int {
        typeMetadata(for: provider.type).preferredMetricCount
    }

    static func supportedOfficialSourceModes(for provider: ProviderDescriptor) -> [OfficialSourceMode] {
        guard provider.family == .official else { return [] }
        return typeMetadata(for: provider.type).supportedSourceModes
    }

    static func supportedOfficialWebModes(for provider: ProviderDescriptor) -> [OfficialWebMode] {
        guard provider.family == .official else { return [] }
        return typeMetadata(for: provider.type).supportedWebModes
    }

    static func supportsOfficialBearerCredentialInput(for provider: ProviderDescriptor) -> Bool {
        guard provider.family == .official else { return false }
        guard provider.auth.kind == .bearer else { return false }
        return typeMetadata(for: provider.type).supportsOfficialBearerCredentialInput
    }

    static var officialRelayDefaultProviderIDs: Set<String> {
        Set(officialRelayDefaultProviderOrder)
    }

    static var officialRelayDefaultProviderOrder: [String] {
        OfficialRelayMetadataCatalog.defaultProviderOrder
    }

    static func officialRelayDefaultProviderID(adapterID: String) -> String? {
        OfficialRelayMetadataCatalog.metadata(forAdapterID: adapterID)?.providerID
    }

    static func officialRelayDisplayName(adapterID: String) -> String? {
        OfficialRelayMetadataCatalog.metadata(forAdapterID: adapterID)?.displayName
    }

    static func officialRelayDefaultBaseURL(adapterID: String) -> String? {
        OfficialRelayMetadataCatalog.metadata(forAdapterID: adapterID)?.baseURL
    }

    static func officialRelayIconName(adapterID: String) -> String? {
        OfficialRelayMetadataCatalog.metadata(forAdapterID: adapterID)?.iconName
    }

    private static func credentialFields(for provider: ProviderDescriptor) -> [CredentialFieldSpec] {
        guard provider.family == .official else { return [] }
        if provider.type == .opencodeGo {
            return [
                CredentialFieldSpec(kind: .opencodeWorkspaceID, storageTarget: .providerToken, requiresExplicitSave: true),
                CredentialFieldSpec(kind: .opencodeManualCookie, storageTarget: .officialManualCookie, requiresExplicitSave: true)
            ]
        }
        if provider.type == .trae {
            return [
                CredentialFieldSpec(kind: .traeAuthorization, storageTarget: .providerToken, requiresExplicitSave: true)
            ]
        }
        if supportsOfficialBearerCredentialInput(for: provider) {
            return [
                CredentialFieldSpec(kind: .bearerToken, storageTarget: .providerToken, requiresExplicitSave: true)
            ]
        }
        if provider.supportsOfficialManualCookieInput {
            return [
                CredentialFieldSpec(kind: .manualCookie, storageTarget: .officialManualCookie, requiresExplicitSave: true)
            ]
        }
        return []
    }

    private static func displayName(for provider: ProviderDescriptor?) -> String {
        guard let provider else { return "第三方中转站" }
        if provider.isRelay {
            if provider.isOfficialRelayProvider,
               let adapterID = provider.officialRelayAdapterID,
               let displayName = officialRelayDisplayName(adapterID: adapterID) {
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
               let iconName = officialRelayIconName(adapterID: adapterID) {
                return iconName
            }
            return relayIconOverrideName(for: provider) ?? "menu_relay_icon"
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

    private static func relayIconOverrideName(for provider: ProviderDescriptor) -> String? {
        guard provider.type == .relay || provider.type == .open || provider.type == .dragon else {
            return nil
        }
        let relayID = (provider.relayConfig?.adapterID ?? provider.relayManifest?.id ?? "").lowercased()
        let relayBaseURL = provider.relayConfig?.baseURL ?? provider.baseURL ?? ""
        let host = URL(string: relayBaseURL)?.host?.lowercased() ?? ""
        let providerName = provider.name.lowercased()
        let relaySignals = "\(relayID)|\(host)|\(providerName)"
        if relaySignals.contains("moonshot") || relaySignals.contains("moonsho") || relaySignals.contains("kimi") {
            return "menu_kimi_icon"
        }
        if relaySignals.contains("deepseek") {
            return "menu_deepseek_icon"
        }
        if relaySignals.contains("xiaomimimo") || relaySignals.contains("mimo") {
            return "menu_mimo_icon"
        }
        if relaySignals.contains("minimax") || relaySignals.contains("minimaxi") {
            return "menu_minimax_icon"
        }
        return nil
    }
}
