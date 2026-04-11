import Foundation

struct RelayProviderConfig: Codable, Equatable {
    var adapterID: String?
    var baseURL: String
    var tokenChannelEnabled: Bool
    var balanceChannelEnabled: Bool
    var balanceAuth: AuthConfig
    var balanceCredentialMode: RelayCredentialMode?
    var manualOverrides: RelayManualOverride?

    init(
        adapterID: String? = nil,
        baseURL: String,
        tokenChannelEnabled: Bool = true,
        balanceChannelEnabled: Bool = false,
        balanceAuth: AuthConfig,
        balanceCredentialMode: RelayCredentialMode? = nil,
        manualOverrides: RelayManualOverride? = nil
    ) {
        self.adapterID = adapterID
        self.baseURL = baseURL
        self.tokenChannelEnabled = tokenChannelEnabled
        self.balanceChannelEnabled = balanceChannelEnabled
        self.balanceAuth = balanceAuth
        self.balanceCredentialMode = balanceCredentialMode
        self.manualOverrides = manualOverrides
    }
}

enum RelayCredentialMode: String, Codable, CaseIterable, Identifiable {
    case manualPreferred
    case browserPreferred
    case browserOnly

    var id: String { rawValue }
}

struct RelayManualOverride: Codable, Equatable {
    var authHeader: String?
    var authScheme: String?
    var userID: String?
    var userIDHeader: String?
    var requestMethod: String?
    var requestBodyJSON: String?
    var endpointPath: String?
    var remainingExpression: String?
    var usedExpression: String?
    var limitExpression: String?
    var successExpression: String?
    var unitExpression: String?
    var accountLabelExpression: String?
    var staticHeaders: [String: String]?

    var isEmpty: Bool {
        authHeader == nil &&
        authScheme == nil &&
        userID == nil &&
        userIDHeader == nil &&
        requestMethod == nil &&
        requestBodyJSON == nil &&
        endpointPath == nil &&
        remainingExpression == nil &&
        usedExpression == nil &&
        limitExpression == nil &&
        successExpression == nil &&
        unitExpression == nil &&
        accountLabelExpression == nil &&
        (staticHeaders?.isEmpty ?? true)
    }
}

enum RelayAuthStrategyKind: String, Codable, CaseIterable {
    case savedBearer
    case browserBearer
    case savedCookieHeader
    case browserCookieHeader
    case namedCookie
    case customHeader
}

struct RelayAuthStrategy: Codable, Equatable {
    var kind: RelayAuthStrategyKind
    var cookieName: String?

    init(kind: RelayAuthStrategyKind, cookieName: String? = nil) {
        self.kind = kind
        self.cookieName = cookieName
    }
}

struct RelayAdapterMatch: Codable, Equatable {
    var hostPatterns: [String]
    var defaultDisplayName: String?
    var defaultTokenChannelEnabled: Bool
    var defaultBalanceChannelEnabled: Bool

    init(
        hostPatterns: [String],
        defaultDisplayName: String? = nil,
        defaultTokenChannelEnabled: Bool = true,
        defaultBalanceChannelEnabled: Bool = false
    ) {
        self.hostPatterns = hostPatterns
        self.defaultDisplayName = defaultDisplayName
        self.defaultTokenChannelEnabled = defaultTokenChannelEnabled
        self.defaultBalanceChannelEnabled = defaultBalanceChannelEnabled
    }
}

enum RelayRequiredInputKind: String, Codable, CaseIterable {
    case displayName
    case baseURL
    case quotaAuth
    case balanceAuth
    case userID
}

struct RelaySetupManifest: Codable, Equatable {
    struct LocalizedText: Codable, Equatable {
        var zhHans: String?
        var en: String?

        init(zhHans: String? = nil, en: String? = nil) {
            self.zhHans = zhHans
            self.en = en
        }
    }

    var recommendedBaseURL: String?
    var requiredInputs: [RelayRequiredInputKind]
    var quotaAuthHint: LocalizedText?
    var balanceAuthHint: LocalizedText?
    var userIDHint: LocalizedText?

    init(
        recommendedBaseURL: String? = nil,
        requiredInputs: [RelayRequiredInputKind] = [],
        quotaAuthHint: LocalizedText? = nil,
        balanceAuthHint: LocalizedText? = nil,
        userIDHint: LocalizedText? = nil
    ) {
        self.recommendedBaseURL = recommendedBaseURL
        self.requiredInputs = requiredInputs
        self.quotaAuthHint = quotaAuthHint
        self.balanceAuthHint = balanceAuthHint
        self.userIDHint = userIDHint
    }
}

struct RelayRequestManifest: Codable, Equatable {
    var method: String
    var path: String
    var bodyJSON: String?
    var headers: [String: String]?
    var userID: String?
    var userIDHeader: String?
    var authHeader: String?
    var authScheme: String?

    init(
        method: String = "GET",
        path: String,
        bodyJSON: String? = nil,
        headers: [String: String]? = nil,
        userID: String? = nil,
        userIDHeader: String? = nil,
        authHeader: String? = nil,
        authScheme: String? = nil
    ) {
        self.method = method
        self.path = path
        self.bodyJSON = bodyJSON
        self.headers = headers
        self.userID = userID
        self.userIDHeader = userIDHeader
        self.authHeader = authHeader
        self.authScheme = authScheme
    }
}

struct RelayTokenRequestManifest: Codable, Equatable {
    var usagePath: String
    var subscriptionPath: String?
    var billingUsagePath: String?

    init(
        usagePath: String = "/api/usage/token/",
        subscriptionPath: String? = "/v1/dashboard/billing/subscription",
        billingUsagePath: String? = "/v1/dashboard/billing/usage"
    ) {
        self.usagePath = usagePath
        self.subscriptionPath = subscriptionPath
        self.billingUsagePath = billingUsagePath
    }
}

struct RelayExtractManifest: Codable, Equatable {
    var success: String?
    var remaining: String
    var used: String?
    var limit: String?
    var unit: String?
    var accountLabel: String?

    init(
        success: String? = nil,
        remaining: String,
        used: String? = nil,
        limit: String? = nil,
        unit: String? = nil,
        accountLabel: String? = nil
    ) {
        self.success = success
        self.remaining = remaining
        self.used = used
        self.limit = limit
        self.unit = unit
        self.accountLabel = accountLabel
    }
}

enum RelayPostprocessID: String, Codable, Equatable {
    case quotaDisplayStatus
}

struct RelayAdapterManifest: Codable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var match: RelayAdapterMatch
    var setup: RelaySetupManifest?
    var authStrategies: [RelayAuthStrategy]
    var balanceRequest: RelayRequestManifest
    var tokenRequest: RelayTokenRequestManifest?
    var extract: RelayExtractManifest
    var postprocessID: RelayPostprocessID?
}
