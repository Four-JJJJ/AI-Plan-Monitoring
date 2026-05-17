import Foundation
import OhMyUsageDomain

public struct UsageProviderSummaryViewState: Equatable, Sendable {
    public let providerID: UsageProviderIdentity
    public let title: String
    public let usedText: String
    public let remainingText: String?
    public let usageRatio: Double?

    public init(
        providerID: UsageProviderIdentity,
        title: String,
        snapshot: UsageQuotaSnapshot
    ) {
        self.providerID = providerID
        self.title = title
        self.usedText = UsageProviderSummaryViewState.format(snapshot.used)
        self.remainingText = snapshot.remaining.map(UsageProviderSummaryViewState.format)
        self.usageRatio = snapshot.usageRatio
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
