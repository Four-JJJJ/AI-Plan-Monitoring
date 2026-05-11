import Foundation

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
        let credentialFields: [CredentialFieldSpec]
        if provider.family != .official {
            credentialFields = []
        } else if provider.type == .opencodeGo {
            credentialFields = [
                CredentialFieldSpec(kind: .opencodeWorkspaceID, storageTarget: .providerToken, requiresExplicitSave: true),
                CredentialFieldSpec(kind: .opencodeManualCookie, storageTarget: .officialManualCookie, requiresExplicitSave: true)
            ]
        } else if provider.type == .trae {
            credentialFields = [
                CredentialFieldSpec(kind: .traeAuthorization, storageTarget: .providerToken, requiresExplicitSave: true)
            ]
        } else if provider.supportsOfficialBearerCredentialInput {
            credentialFields = [
                CredentialFieldSpec(kind: .bearerToken, storageTarget: .providerToken, requiresExplicitSave: true)
            ]
        } else if provider.supportsOfficialManualCookieInput {
            credentialFields = [
                CredentialFieldSpec(kind: .manualCookie, storageTarget: .officialManualCookie, requiresExplicitSave: true)
            ]
        } else {
            credentialFields = []
        }

        return ProviderSettingsSpec(
            providerType: provider.type,
            supportedSourceModes: provider.supportedOfficialSourceModes,
            supportedWebModes: provider.supportedOfficialWebModes,
            credentialFields: credentialFields,
            showsQuotaDisplayPreference: provider.family == .official,
            showsTraeValueDisplayMode: provider.type == .trae
        )
    }
}

extension ProviderDescriptor {
    var supportsOfficialBearerCredentialInput: Bool {
        guard family == .official else { return false }
        guard auth.kind == .bearer else { return false }
        switch type {
        case .openrouterCredits, .openrouterAPI:
            return true
        default:
            return false
        }
    }
}
