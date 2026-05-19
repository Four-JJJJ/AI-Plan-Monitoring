import Foundation
import OhMyUsageDomain

struct RelayProviderDescriptorModelAdapter {
    private let manifestForProvider: (ProviderDescriptor) -> RelayAdapterManifest?
    private let manifestForBaseURL: (String, String?) -> RelayAdapterManifest
    private let adapterIDForBaseURL: (String, String?) -> String
    private let displayModeForProvider: (ProviderDescriptor) -> RelayDisplayMode
    private let viewConfigForProvider: (ProviderDescriptor) -> OpenProviderConfig?
    private let viewConfigForRelayConfig: (RelayProviderConfig, RelayAdapterManifest) -> OpenProviderConfig
    private let defaultRelayConfigForDescriptor: (
        String,
        String?,
        String?,
        AuthConfig,
        OpenProviderConfig?,
        String
    ) -> RelayProviderConfig
    private let defaultRelayBalanceAccountForDescriptor: (String, String?, String) -> String

    static var live: RelayProviderDescriptorModelAdapter {
        RelayProviderDescriptorModelAdapter(resolver: RelayProviderDescriptorResolver())
    }

    init(resolver: RelayProviderDescriptorResolver) {
        self.manifestForProvider = { resolver.manifest(for: $0) }
        self.manifestForBaseURL = { resolver.manifest(for: $0, preferredID: $1) }
        self.adapterIDForBaseURL = { resolver.adapterID(for: $0, preferredID: $1) }
        self.displayModeForProvider = { resolver.displayMode(for: $0) }
        self.viewConfigForProvider = { resolver.viewConfig(for: $0) }
        self.viewConfigForRelayConfig = { resolver.viewConfig(for: $0, manifest: $1) }
        self.defaultRelayConfigForDescriptor = {
            resolver.defaultRelayConfig(
                id: $0,
                baseURL: $1,
                preferredAdapterID: $2,
                auth: $3,
                legacyOpenConfig: $4,
                keychainService: $5
            )
        }
        self.defaultRelayBalanceAccountForDescriptor = {
            resolver.defaultRelayBalanceAccount(id: $0, baseURL: $1, adapterID: $2)
        }
    }

    func manifest(for provider: ProviderDescriptor) -> RelayAdapterManifest? {
        manifestForProvider(provider)
    }

    func manifest(for baseURL: String, preferredID: String? = nil) -> RelayAdapterManifest {
        manifestForBaseURL(baseURL, preferredID)
    }

    func adapterID(for baseURL: String, preferredID: String? = nil) -> String {
        adapterIDForBaseURL(baseURL, preferredID)
    }

    func displayMode(for provider: ProviderDescriptor) -> RelayDisplayMode {
        displayModeForProvider(provider)
    }

    func viewConfig(for provider: ProviderDescriptor) -> OpenProviderConfig? {
        viewConfigForProvider(provider)
    }

    func viewConfig(for relayConfig: RelayProviderConfig, manifest: RelayAdapterManifest) -> OpenProviderConfig {
        viewConfigForRelayConfig(relayConfig, manifest)
    }

    func defaultRelayConfig(
        id: String,
        baseURL: String?,
        preferredAdapterID: String? = nil,
        auth: AuthConfig = AuthConfig.none,
        legacyOpenConfig: OpenProviderConfig? = nil,
        keychainService: String = KeychainService.defaultServiceName
    ) -> RelayProviderConfig {
        defaultRelayConfigForDescriptor(id, baseURL, preferredAdapterID, auth, legacyOpenConfig, keychainService)
    }

    func defaultRelayBalanceAccount(
        id: String,
        baseURL: String?,
        adapterID: String
    ) -> String {
        defaultRelayBalanceAccountForDescriptor(id, baseURL, adapterID)
    }
}

extension ProviderDescriptor {
    var relayManifest: RelayAdapterManifest? {
        RelayProviderDescriptorModelAdapter.live.manifest(for: self)
    }

    var relayDisplayMode: RelayDisplayMode {
        RelayProviderDescriptorModelAdapter.live.displayMode(for: self)
    }

    var relayViewConfig: OpenProviderConfig? {
        RelayProviderDescriptorModelAdapter.live.viewConfig(for: self)
    }
}
