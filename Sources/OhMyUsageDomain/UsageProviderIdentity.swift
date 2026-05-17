import Foundation

public struct UsageProviderIdentity: Hashable, Sendable {
    public let rawValue: String

    public init?(_ rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }
        self.rawValue = normalized
    }
}
