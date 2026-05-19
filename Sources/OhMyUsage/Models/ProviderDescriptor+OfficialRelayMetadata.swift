import Foundation

extension ProviderDescriptor {
    var officialRelayAdapterID: String? {
        guard isRelay else { return nil }
        let adapterID = relayConfig?.adapterID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let adapterID, !adapterID.isEmpty {
            return adapterID
        }
        let normalizedBaseURL = Self.normalizeRelayBaseURL(relayConfig?.baseURL ?? baseURL ?? "")
        return RelayProviderDescriptorModelAdapter.live.adapterID(for: normalizedBaseURL)
    }

    var isOfficialRelayProvider: Bool {
        guard isRelay else { return false }
        if Self.officialRelayDefaultProviderIDs.contains(id) {
            return true
        }
        guard let adapterID = officialRelayAdapterID else { return false }
        guard Self.officialRelayDefaultProviderID(adapterID: adapterID) != nil,
              let officialBaseURL = Self.officialRelayDefaultBaseURL(adapterID: adapterID) else {
            return false
        }
        let normalizedBaseURL = Self.normalizeRelayBaseURL(relayConfig?.baseURL ?? baseURL ?? "")
            .lowercased()
        return !normalizedBaseURL.isEmpty
            && normalizedBaseURL == Self.normalizeRelayBaseURL(officialBaseURL).lowercased()
    }

    var officialRelayDefaultProviderID: String? {
        guard let adapterID = officialRelayAdapterID else { return nil }
        return Self.officialRelayDefaultProviderID(adapterID: adapterID)
    }

    static var officialRelayDefaultProviderIDs: Set<String> {
        Set(OfficialRelayMetadataCatalog.defaultProviderOrder)
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
}
