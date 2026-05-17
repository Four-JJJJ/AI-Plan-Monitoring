import Foundation

extension ProviderDescriptor {
    var legacyRelayImportIdentity: String? {
        guard family == .thirdParty, isRelay else {
            return nil
        }

        let normalizedBaseURL = Self.normalizeRelayBaseURL(
            relayConfig?.baseURL ?? baseURL ?? ""
        ).lowercased()
        guard !normalizedBaseURL.isEmpty else {
            return nil
        }

        let normalizedAdapterID = relayConfig?.adapterID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let adapterID = (normalizedAdapterID?.isEmpty == false ? normalizedAdapterID : nil)
            ?? RelayProviderDescriptorModelAdapter.live.adapterID(for: normalizedBaseURL).lowercased()
        return "\(normalizedBaseURL)|\(adapterID)"
    }

    var isLegacyRelayExample: Bool {
        guard family == .thirdParty, type == .relay else {
            return false
        }

        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedID == "status-provider-first" || normalizedID == "status-provider-second" {
            return true
        }

        let normalizedBaseURL = Self.normalizeRelayBaseURL(
            relayConfig?.baseURL ?? baseURL ?? ""
        )
        let host = URL(string: normalizedBaseURL)?.host?.lowercased()
        if let host,
           host == "relay.example.com"
            || host.hasSuffix(".relay.example.com")
            || host == "relay-fixture.dev"
            || host.hasSuffix(".relay-fixture.dev")
            || host == "relay-preference.dev"
            || host.hasSuffix(".relay-preference.dev")
            || host == "first-status-provider.test"
            || host == "second-status-provider.test" {
            return true
        }

        let normalizedAdapterID = relayConfig?.adapterID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let usesGenericRelayTemplate = normalizedAdapterID == nil
            || normalizedAdapterID == ""
            || normalizedAdapterID == "generic-newapi"

        if usesGenericRelayTemplate,
           let host,
           host == "example.com" || host.hasSuffix(".example.com") {
            return true
        }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (usesGenericRelayTemplate && normalizedName.contains("relay example"))
            || (usesGenericRelayTemplate && normalizedName == "relay fixture")
            || normalizedID.hasPrefix("open-relay-example")
            || normalizedID.hasPrefix("open-relay-fixture")
            || normalizedID.hasPrefix("open-relay-preference")
    }
}
