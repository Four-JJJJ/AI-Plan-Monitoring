import Foundation
import OhMyUsageDomain

extension AuthConfig {
    func withFallback(service: String, account: String?) -> AuthConfig {
        AuthConfig(
            kind: kind,
            keychainService: keychainService ?? service,
            keychainAccount: keychainAccount ?? account
        )
    }

    func normalizedCredentialServiceName() -> AuthConfig {
        let normalizedService: String?
        if let keychainService {
            let trimmed = keychainService.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || KeychainService.isLegacyServiceName(trimmed) {
                normalizedService = KeychainService.defaultServiceName
            } else {
                normalizedService = trimmed
            }
        } else {
            normalizedService = nil
        }

        return AuthConfig(
            kind: kind,
            keychainService: normalizedService,
            keychainAccount: keychainAccount
        )
    }
}
