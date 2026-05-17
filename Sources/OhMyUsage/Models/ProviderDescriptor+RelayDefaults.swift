import Foundation

extension ProviderDescriptor {
    static func makeOpenRelay(
        name: String,
        baseURL: String,
        preferredAdapterID: String? = nil,
        keychainService: String = KeychainService.defaultServiceName
    ) -> ProviderDescriptor {
        let normalizedBaseURL = Self.normalizeRelayBaseURL(baseURL)
        let host = URL(string: normalizedBaseURL)?.host ?? "relay"
        let hostSlug = host.replacingOccurrences(of: ".", with: "-")
        let id = "open-\(hostSlug)-\(Int(Date().timeIntervalSince1970))"
        return ProviderDescriptor(
            id: id,
            name: name.isEmpty ? host : name,
            family: .thirdParty,
            type: .relay,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .bearer, keychainService: keychainService, keychainAccount: "\(host)/sk-token"),
            baseURL: normalizedBaseURL,
            relayConfig: defaultRelayConfig(
                id: id,
                baseURL: normalizedBaseURL,
                preferredAdapterID: preferredAdapterID,
                auth: AuthConfig(kind: .bearer, keychainService: keychainService, keychainAccount: "\(host)/sk-token")
            )
        )
    }

    static func defaultRelayConfig(
        id: String,
        baseURL: String?,
        preferredAdapterID: String? = nil,
        auth: AuthConfig = AuthConfig.none,
        legacyOpenConfig: OpenProviderConfig? = nil,
        keychainService: String = KeychainService.defaultServiceName
    ) -> RelayProviderConfig {
        RelayProviderDescriptorModelAdapter.live.defaultRelayConfig(
            id: id,
            baseURL: baseURL,
            preferredAdapterID: preferredAdapterID,
            auth: auth,
            legacyOpenConfig: legacyOpenConfig,
            keychainService: keychainService
        )
    }

    static func defaultRelayBalanceAccount(
        id: String,
        baseURL: String?,
        adapterID: String
    ) -> String {
        RelayProviderDescriptorModelAdapter.live.defaultRelayBalanceAccount(
            id: id,
            baseURL: baseURL,
            adapterID: adapterID
        )
    }

    static func normalizeRelayBaseURL(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            return ""
        }
        if !value.contains("://") {
            value = "https://" + value
        }
        if var components = URLComponents(string: value),
           let host = components.host, !host.isEmpty {
            components.path = ""
            components.query = nil
            components.fragment = nil
            components.user = nil
            components.password = nil
            components.scheme = components.scheme ?? "https"
            if var normalized = components.string {
                while normalized.hasSuffix("/") {
                    normalized.removeLast()
                }
                return normalized
            }
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
