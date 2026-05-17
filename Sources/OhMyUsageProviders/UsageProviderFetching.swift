import Foundation
import OhMyUsageDomain

public protocol UsageProviderFetching: Sendable {
    var providerID: UsageProviderIdentity { get }

    func fetchUsageSnapshot(forceRefresh: Bool) async throws -> UsageQuotaSnapshot
}
