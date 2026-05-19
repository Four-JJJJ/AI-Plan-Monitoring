import Foundation
import OhMyUsageDomain

enum CredentialFieldKind: String, Equatable {
    case bearerToken
    case manualCookie
    case opencodeWorkspaceID
    case opencodeManualCookie
    case traeAuthorization
}

enum CredentialStorageTarget: Equatable {
    case providerToken
    case officialManualCookie
}

struct CredentialFieldSpec: Equatable, Identifiable {
    var kind: CredentialFieldKind
    var storageTarget: CredentialStorageTarget
    var requiresExplicitSave: Bool

    var id: String { kind.rawValue }
}

struct ProviderSettingsSpec: Equatable {
    var providerType: ProviderType
    var supportedSourceModes: [OfficialSourceMode]
    var supportedWebModes: [OfficialWebMode]
    var credentialFields: [CredentialFieldSpec]
    var showsQuotaDisplayPreference: Bool
    var showsTraeValueDisplayMode: Bool

    static func resolve(for provider: ProviderDescriptor) -> ProviderSettingsSpec {
        ProviderDefinitionRegistry.settingsSpec(for: provider)
    }
}

extension ProviderDescriptor {
    var supportsOfficialBearerCredentialInput: Bool {
        ProviderDefinitionRegistry.settingsSpec(for: self).credentialFields.contains { field in
            field.kind == .bearerToken
        }
    }
}
