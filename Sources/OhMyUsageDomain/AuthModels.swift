import Foundation

public enum AuthKind: String, Codable, Sendable {
    case none
    case bearer
    case localCodex
}

public struct AuthConfig: Codable, Equatable, Sendable {
    public var kind: AuthKind
    public var keychainService: String?
    public var keychainAccount: String?

    public static let none = AuthConfig(kind: .none)

    public init(kind: AuthKind, keychainService: String? = nil, keychainAccount: String? = nil) {
        self.kind = kind
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
    }
}

public struct AlertRule: Codable, Equatable, Sendable {
    public var lowRemaining: Double
    public var maxConsecutiveFailures: Int
    public var notifyOnAuthError: Bool

    public init(lowRemaining: Double, maxConsecutiveFailures: Int, notifyOnAuthError: Bool) {
        self.lowRemaining = lowRemaining
        self.maxConsecutiveFailures = maxConsecutiveFailures
        self.notifyOnAuthError = notifyOnAuthError
    }
}
