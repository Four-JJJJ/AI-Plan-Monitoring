import Foundation
import OhMyUsageDomain

struct AppCredentialMutationOutcome: Equatable {
    var didPersistCredential: Bool = false
    var shouldBumpLookupVersion: Bool = false

    static let none = AppCredentialMutationOutcome()
}

struct AppProviderCredentialCoordinator {
    func saveToken(
        _ token: String,
        descriptor: ProviderDescriptor,
        normalize: (String, AuthKind) -> String,
        saveCredential: (String, String, String) -> Bool
    ) -> AppCredentialMutationOutcome {
        guard let service = descriptor.auth.keychainService,
              let account = descriptor.auth.keychainAccount else {
            return .none
        }

        let normalized = normalize(token, descriptor.auth.kind)
        guard !normalized.isEmpty else { return .none }
        let ok = saveCredential(normalized, service, account)
        return AppCredentialMutationOutcome(
            didPersistCredential: ok,
            shouldBumpLookupVersion: ok
        )
    }

    func saveToken(
        _ token: String,
        auth: AuthConfig,
        normalize: (String, AuthKind) -> String,
        saveCredential: (String, String, String) -> Bool
    ) -> AppCredentialMutationOutcome {
        guard let service = auth.keychainService,
              let account = auth.keychainAccount else {
            return .none
        }

        let normalized = normalize(token, auth.kind)
        guard !normalized.isEmpty else { return .none }
        let ok = saveCredential(normalized, service, account)
        return AppCredentialMutationOutcome(
            didPersistCredential: ok,
            shouldBumpLookupVersion: ok
        )
    }

    func saveOfficialManualCookie(
        _ value: String,
        providerID: String,
        providers: [ProviderDescriptor],
        saveCredential: (String, String, String) -> Bool
    ) -> AppCredentialMutationOutcome {
        guard let provider = providers.first(where: { $0.id == providerID }),
              provider.family == .official,
              let account = provider.officialConfig?.manualCookieAccount else {
            return .none
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        let ok = saveCredential(trimmed, KeychainService.defaultServiceName, account)
        return AppCredentialMutationOutcome(
            didPersistCredential: ok,
            shouldBumpLookupVersion: ok
        )
    }

    func invalidateLookupCache(_ invalidate: () -> Void) -> AppCredentialMutationOutcome {
        invalidate()
        return AppCredentialMutationOutcome(
            didPersistCredential: false,
            shouldBumpLookupVersion: true
        )
    }
}
