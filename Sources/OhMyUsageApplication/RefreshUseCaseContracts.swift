import Foundation
import OhMyUsageDomain

public struct UsageRefreshRequest: Equatable, Sendable {
    public let providerID: UsageProviderIdentity
    public let forceRefresh: Bool

    public init(providerID: UsageProviderIdentity, forceRefresh: Bool) {
        self.providerID = providerID
        self.forceRefresh = forceRefresh
    }
}

public protocol UsageRefreshUseCase: Sendable {
    func refreshUsage(_ request: UsageRefreshRequest) async throws -> UsageQuotaSnapshot
}
