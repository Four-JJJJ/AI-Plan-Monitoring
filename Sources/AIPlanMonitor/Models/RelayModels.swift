import Foundation

struct RelayProviderConfig: Codable, Equatable {
    var adapterID: String?
    var baseURL: String
    var tokenChannelEnabled: Bool
    var balanceChannelEnabled: Bool
    var balanceAuth: AuthConfig
    var balanceCredentialMode: RelayCredentialMode?
    var quotaDisplayMode: OfficialQuotaDisplayMode
    var manualOverrides: RelayManualOverride?

    init(
        adapterID: String? = nil,
        baseURL: String,
        tokenChannelEnabled: Bool = true,
        balanceChannelEnabled: Bool = false,
        balanceAuth: AuthConfig,
        balanceCredentialMode: RelayCredentialMode? = nil,
        quotaDisplayMode: OfficialQuotaDisplayMode = .remaining,
        manualOverrides: RelayManualOverride? = nil
    ) {
        self.adapterID = adapterID
        self.baseURL = baseURL
        self.tokenChannelEnabled = tokenChannelEnabled
        self.balanceChannelEnabled = balanceChannelEnabled
        self.balanceAuth = balanceAuth
        self.balanceCredentialMode = balanceCredentialMode
        self.quotaDisplayMode = quotaDisplayMode
        self.manualOverrides = manualOverrides
    }

    private enum CodingKeys: String, CodingKey {
        case adapterID
        case baseURL
        case tokenChannelEnabled
        case balanceChannelEnabled
        case balanceAuth
        case balanceCredentialMode
        case quotaDisplayMode
        case manualOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.adapterID = try container.decodeIfPresent(String.self, forKey: .adapterID)
        self.baseURL = try container.decode(String.self, forKey: .baseURL)
        self.tokenChannelEnabled = try container.decodeIfPresent(Bool.self, forKey: .tokenChannelEnabled) ?? true
        self.balanceChannelEnabled = try container.decodeIfPresent(Bool.self, forKey: .balanceChannelEnabled) ?? false
        self.balanceAuth = try container.decode(AuthConfig.self, forKey: .balanceAuth)
        self.balanceCredentialMode = try container.decodeIfPresent(RelayCredentialMode.self, forKey: .balanceCredentialMode)
        self.quotaDisplayMode = try container.decodeIfPresent(OfficialQuotaDisplayMode.self, forKey: .quotaDisplayMode) ?? .remaining
        self.manualOverrides = try container.decodeIfPresent(RelayManualOverride.self, forKey: .manualOverrides)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(adapterID, forKey: .adapterID)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(tokenChannelEnabled, forKey: .tokenChannelEnabled)
        try container.encode(balanceChannelEnabled, forKey: .balanceChannelEnabled)
        try container.encode(balanceAuth, forKey: .balanceAuth)
        try container.encodeIfPresent(balanceCredentialMode, forKey: .balanceCredentialMode)
        try container.encode(quotaDisplayMode, forKey: .quotaDisplayMode)
        try container.encodeIfPresent(manualOverrides, forKey: .manualOverrides)
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
    var diagnosticHints: LocalizedText?

    init(
        recommendedBaseURL: String? = nil,
        requiredInputs: [RelayRequiredInputKind] = [],
        quotaAuthHint: LocalizedText? = nil,
        balanceAuthHint: LocalizedText? = nil,
        userIDHint: LocalizedText? = nil,
        diagnosticHints: LocalizedText? = nil
    ) {
        self.recommendedBaseURL = recommendedBaseURL
        self.requiredInputs = requiredInputs
        self.quotaAuthHint = quotaAuthHint
        self.balanceAuthHint = balanceAuthHint
        self.userIDHint = userIDHint
        self.diagnosticHints = diagnosticHints
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
    var displayMode: RelayDisplayMode
    var supportsBrowserFallback: Bool
    var supportsSeparateBalanceAuth: Bool
    var balanceRequest: RelayRequestManifest
    var tokenRequest: RelayTokenRequestManifest?
    var extract: RelayExtractManifest
    var postprocessID: RelayPostprocessID?

    init(
        id: String,
        displayName: String,
        match: RelayAdapterMatch,
        setup: RelaySetupManifest? = nil,
        authStrategies: [RelayAuthStrategy],
        displayMode: RelayDisplayMode = .balance,
        supportsBrowserFallback: Bool = true,
        supportsSeparateBalanceAuth: Bool = true,
        balanceRequest: RelayRequestManifest,
        tokenRequest: RelayTokenRequestManifest? = nil,
        extract: RelayExtractManifest,
        postprocessID: RelayPostprocessID? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.match = match
        self.setup = setup
        self.authStrategies = authStrategies
        self.displayMode = displayMode
        self.supportsBrowserFallback = supportsBrowserFallback
        self.supportsSeparateBalanceAuth = supportsSeparateBalanceAuth
        self.balanceRequest = balanceRequest
        self.tokenRequest = tokenRequest
        self.extract = extract
        self.postprocessID = postprocessID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case match
        case setup
        case authStrategies
        case displayMode
        case supportsBrowserFallback
        case supportsSeparateBalanceAuth
        case balanceRequest
        case tokenRequest
        case extract
        case postprocessID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        match = try container.decode(RelayAdapterMatch.self, forKey: .match)
        setup = try container.decodeIfPresent(RelaySetupManifest.self, forKey: .setup)
        authStrategies = try container.decode([RelayAuthStrategy].self, forKey: .authStrategies)
        displayMode = try container.decodeIfPresent(RelayDisplayMode.self, forKey: .displayMode) ?? .balance
        supportsBrowserFallback = try container.decodeIfPresent(Bool.self, forKey: .supportsBrowserFallback) ?? true
        supportsSeparateBalanceAuth = try container.decodeIfPresent(Bool.self, forKey: .supportsSeparateBalanceAuth) ?? true
        balanceRequest = try container.decode(RelayRequestManifest.self, forKey: .balanceRequest)
        tokenRequest = try container.decodeIfPresent(RelayTokenRequestManifest.self, forKey: .tokenRequest)
        extract = try container.decode(RelayExtractManifest.self, forKey: .extract)
        postprocessID = try container.decodeIfPresent(RelayPostprocessID.self, forKey: .postprocessID)
    }
}
