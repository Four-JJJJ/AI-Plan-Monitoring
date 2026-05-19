import Foundation
import OhMyUsageDomain

extension ProviderDescriptor {
    // Legacy migration/test fixtures only. New code should create third-party relays
    // through makeOpenRelay/defaultRelayConfig or decoded migration paths.
    static func legacyDefaultDragon() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "dragoncode",
            name: "dragoncode.codes",
            family: .thirdParty,
            type: .relay,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .bearer, keychainService: KeychainService.defaultServiceName, keychainAccount: "dragoncode.codes/auth_token"),
            baseURL: "https://dragoncode.codes",
            relayConfig: RelayProviderConfig(
                adapterID: "dragoncode",
                baseURL: "https://dragoncode.codes",
                tokenChannelEnabled: false,
                balanceChannelEnabled: true,
                balanceAuth: AuthConfig(
                    kind: .bearer,
                    keychainService: KeychainService.defaultServiceName,
                    keychainAccount: "dragoncode.codes/auth_token"
                ),
                manualOverrides: RelayManualOverride(
                    authHeader: "Authorization",
                    authScheme: "Bearer",
                    userID: nil,
                    userIDHeader: nil,
                    requestMethod: "GET",
                    requestBodyJSON: nil,
                    endpointPath: "/api/v1/auth/me",
                    remainingExpression: "data.balance",
                    usedExpression: nil,
                    limitExpression: nil,
                    successExpression: nil,
                    unitExpression: "balance",
                    accountLabelExpression: nil,
                    staticHeaders: nil
                )
            )
        )
    }

    // Legacy migration/test fixtures only. New code should create third-party relays
    // through makeOpenRelay/defaultRelayConfig or decoded migration paths.
    static func legacyDefaultHongmacc() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "hongmacc",
            name: "hongmacc.com",
            family: .thirdParty,
            type: .relay,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .bearer, keychainService: KeychainService.defaultServiceName, keychainAccount: "hongmacc.com/auth_token"),
            baseURL: "https://hongmacc.com",
            relayConfig: RelayProviderConfig(
                adapterID: "hongmacc",
                baseURL: "https://hongmacc.com",
                tokenChannelEnabled: false,
                balanceChannelEnabled: true,
                balanceAuth: AuthConfig(
                    kind: .bearer,
                    keychainService: KeychainService.defaultServiceName,
                    keychainAccount: "hongmacc.com/auth_token"
                ),
                manualOverrides: RelayManualOverride(
                    authHeader: "Authorization",
                    authScheme: "Bearer",
                    userID: nil,
                    userIDHeader: nil,
                    requestMethod: "GET",
                    requestBodyJSON: nil,
                    endpointPath: "/api/user/assets",
                    remainingExpression: "sum(quotaCards.*.remainingQuota)",
                    usedExpression: nil,
                    limitExpression: nil,
                    successExpression: nil,
                    unitExpression: "CNY",
                    accountLabelExpression: nil,
                    staticHeaders: nil
                )
            )
        )
    }
}
