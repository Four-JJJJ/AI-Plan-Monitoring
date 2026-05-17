import OhMyUsageDomain

public struct UsageFeatureDescriptor: Equatable, Sendable {
    public let providerID: UsageProviderIdentity
    public let title: String
    public let defaultForceRefresh: Bool

    public init(
        providerID: UsageProviderIdentity,
        title: String,
        defaultForceRefresh: Bool = false
    ) {
        self.providerID = providerID
        self.title = title
        self.defaultForceRefresh = defaultForceRefresh
    }
}
