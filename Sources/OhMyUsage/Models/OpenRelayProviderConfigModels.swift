import Foundation

struct OpenProviderConfig: Codable, Equatable {
    var tokenUsageEnabled: Bool
    var accountBalance: RelayAccountBalanceConfig?
}

struct RelayAccountBalanceConfig: Codable, Equatable {
    var enabled: Bool
    var auth: AuthConfig
    var authHeader: String
    var authScheme: String
    var requestMethod: String?
    var requestBodyJSON: String?
    var endpointPath: String
    var userID: String?
    var userIDHeader: String
    var remainingJSONPath: String
    var usedJSONPath: String?
    var limitJSONPath: String?
    var successJSONPath: String?
    var unit: String
}
