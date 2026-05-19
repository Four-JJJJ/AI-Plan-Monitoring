import Foundation
import OhMyUsageDomain

enum RelayProviderDefaultCatalog {
    static func makeOpenRelay(
        name: String,
        baseURL: String,
        preferredAdapterID: String? = nil,
        keychainService: String = KeychainService.defaultServiceName
    ) -> ProviderDescriptor {
        let normalizedBaseURL = normalizeBaseURL(baseURL)
        let host = URL(string: normalizedBaseURL)?.host ?? "relay"
        let hostSlug = host.replacingOccurrences(of: ".", with: "-")
        let id = "open-\(hostSlug)-\(Int(Date().timeIntervalSince1970))"
        let auth = AuthConfig(kind: .bearer, keychainService: keychainService, keychainAccount: "\(host)/sk-token")
        return ProviderDescriptor(
            id: id,
            name: name.isEmpty ? host : name,
            family: .thirdParty,
            type: .relay,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: auth,
            baseURL: normalizedBaseURL,
            relayConfig: defaultConfig(
                id: id,
                baseURL: normalizedBaseURL,
                preferredAdapterID: preferredAdapterID,
                auth: auth
            )
        )
    }

    static func defaultOpenAilinyu() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "open-ailinyu",
            name: "open.ailinyu.de",
            family: .thirdParty,
            type: .relay,
            enabled: false,
            pollIntervalSec: 120,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .bearer, keychainService: KeychainService.defaultServiceName, keychainAccount: "open.ailinyu.de/sk-token"),
            baseURL: "https://open.ailinyu.de",
            relayConfig: RelayProviderConfig(
                adapterID: "ailinyu",
                baseURL: "https://open.ailinyu.de",
                tokenChannelEnabled: false,
                balanceChannelEnabled: true,
                balanceAuth: AuthConfig(
                    kind: .bearer,
                    keychainService: KeychainService.defaultServiceName,
                    keychainAccount: "open.ailinyu.de/session-cookie"
                ),
                manualOverrides: RelayManualOverride(
                    authHeader: "Cookie",
                    authScheme: "",
                    userID: nil,
                    userIDHeader: "New-Api-User",
                    requestMethod: "GET",
                    requestBodyJSON: nil,
                    endpointPath: "/api/user/self",
                    remainingExpression: "data.quota",
                    usedExpression: "data.used_quota",
                    limitExpression: "data.request_quota",
                    successExpression: "success",
                    unitExpression: "quota",
                    accountLabelExpression: nil,
                    staticHeaders: nil
                )
            )
        )
    }

    static func defaultConfig(
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

    static func defaultBalanceAccount(
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

    static func normalizeBaseURL(_ raw: String) -> String {
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
