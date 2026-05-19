import Foundation
import OhMyUsageDomain

extension ProviderDescriptor {
    static func makeOpenRelay(
        name: String,
        baseURL: String,
        preferredAdapterID: String? = nil,
        keychainService: String = KeychainService.defaultServiceName
    ) -> ProviderDescriptor {
        RelayProviderDefaultCatalog.makeOpenRelay(
            name: name,
            baseURL: baseURL,
            preferredAdapterID: preferredAdapterID,
            keychainService: keychainService
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
        RelayProviderDefaultCatalog.defaultConfig(
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
        RelayProviderDefaultCatalog.defaultBalanceAccount(
            id: id,
            baseURL: baseURL,
            adapterID: adapterID
        )
    }

    static func normalizeRelayBaseURL(_ raw: String) -> String {
        RelayProviderDefaultCatalog.normalizeBaseURL(raw)
    }
}
