import Foundation
import OhMyUsageDomain

@MainActor
struct AppCredentialLookupCoordinator {
    func credentialExists(
        for descriptor: ProviderDescriptor,
        secureStorageReady: Bool,
        lookupVersion: Int,
        credentialAccessService: CredentialAccessService,
        onLookupStateChanged: @escaping @MainActor () -> Void
    ) -> Bool {
        credentialExists(
            service: descriptor.auth.keychainService,
            account: descriptor.auth.keychainAccount,
            secureStorageReady: secureStorageReady,
            lookupVersion: lookupVersion,
            credentialAccessService: credentialAccessService,
            onLookupStateChanged: onLookupStateChanged
        )
    }

    func savedCredentialLength(
        for descriptor: ProviderDescriptor,
        secureStorageReady: Bool,
        lookupVersion: Int,
        credentialAccessService: CredentialAccessService,
        onLookupStateChanged: @escaping @MainActor () -> Void
    ) -> Int? {
        savedCredentialLength(
            service: descriptor.auth.keychainService,
            account: descriptor.auth.keychainAccount,
            secureStorageReady: secureStorageReady,
            lookupVersion: lookupVersion,
            credentialAccessService: credentialAccessService,
            onLookupStateChanged: onLookupStateChanged
        )
    }

    func credentialExists(
        auth: AuthConfig,
        secureStorageReady: Bool,
        lookupVersion: Int,
        credentialAccessService: CredentialAccessService,
        onLookupStateChanged: @escaping @MainActor () -> Void
    ) -> Bool {
        credentialExists(
            service: auth.keychainService,
            account: auth.keychainAccount,
            secureStorageReady: secureStorageReady,
            lookupVersion: lookupVersion,
            credentialAccessService: credentialAccessService,
            onLookupStateChanged: onLookupStateChanged
        )
    }

    func savedCredentialLength(
        auth: AuthConfig,
        secureStorageReady: Bool,
        lookupVersion: Int,
        credentialAccessService: CredentialAccessService,
        onLookupStateChanged: @escaping @MainActor () -> Void
    ) -> Int? {
        savedCredentialLength(
            service: auth.keychainService,
            account: auth.keychainAccount,
            secureStorageReady: secureStorageReady,
            lookupVersion: lookupVersion,
            credentialAccessService: credentialAccessService,
            onLookupStateChanged: onLookupStateChanged
        )
    }

    func manualCookieExists(
        for provider: ProviderDescriptor,
        secureStorageReady: Bool,
        lookupVersion: Int,
        credentialAccessService: CredentialAccessService,
        onLookupStateChanged: @escaping @MainActor () -> Void
    ) -> Bool {
        guard provider.family == .official,
              let account = provider.officialConfig?.manualCookieAccount else {
            return false
        }
        return credentialExists(
            service: KeychainService.defaultServiceName,
            account: account,
            secureStorageReady: secureStorageReady,
            lookupVersion: lookupVersion,
            credentialAccessService: credentialAccessService,
            onLookupStateChanged: onLookupStateChanged
        )
    }

    func savedManualCookieLength(
        for provider: ProviderDescriptor,
        secureStorageReady: Bool,
        lookupVersion: Int,
        credentialAccessService: CredentialAccessService,
        onLookupStateChanged: @escaping @MainActor () -> Void
    ) -> Int? {
        guard provider.family == .official,
              let account = provider.officialConfig?.manualCookieAccount else {
            return nil
        }
        return savedCredentialLength(
            service: KeychainService.defaultServiceName,
            account: account,
            secureStorageReady: secureStorageReady,
            lookupVersion: lookupVersion,
            credentialAccessService: credentialAccessService,
            onLookupStateChanged: onLookupStateChanged
        )
    }

    private func credentialExists(
        service: String?,
        account: String?,
        secureStorageReady: Bool,
        lookupVersion: Int,
        credentialAccessService: CredentialAccessService,
        onLookupStateChanged: @escaping @MainActor () -> Void
    ) -> Bool {
        savedCredentialLength(
            service: service,
            account: account,
            secureStorageReady: secureStorageReady,
            lookupVersion: lookupVersion,
            credentialAccessService: credentialAccessService,
            onLookupStateChanged: onLookupStateChanged
        ) != nil
    }

    private func savedCredentialLength(
        service: String?,
        account: String?,
        secureStorageReady: Bool,
        lookupVersion: Int,
        credentialAccessService: CredentialAccessService,
        onLookupStateChanged: @escaping @MainActor () -> Void
    ) -> Int? {
        _ = lookupVersion
        return credentialAccessService.savedCredentialLength(
            service: service,
            account: account,
            secureStorageReady: secureStorageReady,
            onLookupStateChanged: onLookupStateChanged
        )
    }
}
