import OhMyUsageApplication
import OhMyUsageDomain
import OhMyUsagePresentation

public struct UsageFeatureAssembly: Sendable {
    public init() {}

    public func makeUsageFeatureDescriptor(
        providerID: UsageProviderIdentity,
        title: String,
        defaultForceRefresh: Bool = false
    ) -> UsageFeatureDescriptor {
        UsageFeatureDescriptor(
            providerID: providerID,
            title: title,
            defaultForceRefresh: defaultForceRefresh
        )
    }

    public func makeRefreshRequest(
        for descriptor: UsageFeatureDescriptor,
        forceRefresh: Bool? = nil
    ) -> UsageRefreshRequest {
        makeRefreshRequest(
            providerID: descriptor.providerID,
            forceRefresh: forceRefresh ?? descriptor.defaultForceRefresh
        )
    }

    public func makeRefreshRequest(
        providerID: UsageProviderIdentity,
        forceRefresh: Bool = false
    ) -> UsageRefreshRequest {
        UsageRefreshRequest(providerID: providerID, forceRefresh: forceRefresh)
    }

    public func makeSummaryViewState(
        for descriptor: UsageFeatureDescriptor,
        snapshot: UsageQuotaSnapshot
    ) -> UsageProviderSummaryViewState {
        makeSummaryViewState(
            providerID: descriptor.providerID,
            title: descriptor.title,
            snapshot: snapshot
        )
    }

    public func makeSummaryViewState(
        providerID: UsageProviderIdentity,
        title: String,
        snapshot: UsageQuotaSnapshot
    ) -> UsageProviderSummaryViewState {
        UsageProviderSummaryViewState(
            providerID: providerID,
            title: title,
            snapshot: snapshot
        )
    }
}
