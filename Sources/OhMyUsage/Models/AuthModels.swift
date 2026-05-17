import Foundation

enum AuthKind: String, Codable {
    case none
    case bearer
    case localCodex
}

struct AuthConfig: Codable, Equatable {
    var kind: AuthKind
    var keychainService: String?
    var keychainAccount: String?

    static let none = AuthConfig(kind: .none)

    init(kind: AuthKind, keychainService: String? = nil, keychainAccount: String? = nil) {
        self.kind = kind
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
    }
}

struct AlertRule: Codable, Equatable {
    var lowRemaining: Double
    var maxConsecutiveFailures: Int
    var notifyOnAuthError: Bool
}
