import Foundation

public struct OpenProviderConfig: Codable, Equatable, Sendable {
    public var tokenUsageEnabled: Bool
    public var accountBalance: RelayAccountBalanceConfig?

    public init(
        tokenUsageEnabled: Bool,
        accountBalance: RelayAccountBalanceConfig? = nil
    ) {
        self.tokenUsageEnabled = tokenUsageEnabled
        self.accountBalance = accountBalance
    }
}

public struct RelayAccountBalanceConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var auth: AuthConfig
    public var authHeader: String
    public var authScheme: String
    public var requestMethod: String?
    public var requestBodyJSON: String?
    public var endpointPath: String
    public var userID: String?
    public var userIDHeader: String?
    public var remainingJSONPath: String
    public var usedJSONPath: String?
    public var limitJSONPath: String?
    public var successJSONPath: String?
    public var unit: String

    public init(
        enabled: Bool,
        auth: AuthConfig,
        authHeader: String,
        authScheme: String,
        requestMethod: String? = nil,
        requestBodyJSON: String? = nil,
        endpointPath: String,
        userID: String? = nil,
        userIDHeader: String? = nil,
        remainingJSONPath: String,
        usedJSONPath: String? = nil,
        limitJSONPath: String? = nil,
        successJSONPath: String? = nil,
        unit: String
    ) {
        self.enabled = enabled
        self.auth = auth
        self.authHeader = authHeader
        self.authScheme = authScheme
        self.requestMethod = requestMethod
        self.requestBodyJSON = requestBodyJSON
        self.endpointPath = endpointPath
        self.userID = userID
        self.userIDHeader = userIDHeader
        self.remainingJSONPath = remainingJSONPath
        self.usedJSONPath = usedJSONPath
        self.limitJSONPath = limitJSONPath
        self.successJSONPath = successJSONPath
        self.unit = unit
    }
}
