import Foundation
import OhMyUsageDomain

extension ProviderDescriptor {
    static func defaultOfficialBaseURL(type: ProviderType) -> String {
        OfficialProviderDefaultCatalog.baseURL(for: type)
    }

    static func defaultOfficialConfig(type: ProviderType) -> OfficialProviderConfig {
        OfficialProviderDefaultCatalog.config(for: type)
    }

    static func defaultKimiConfig(auth: AuthConfig) -> KimiProviderConfig {
        OfficialProviderDefaultCatalog.kimiConfig(auth: auth)
    }
}
