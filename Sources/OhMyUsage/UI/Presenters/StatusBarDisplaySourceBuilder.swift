import OhMyUsageDomain
import Foundation

enum StatusBarDisplaySourceBuilder {
    static func displaySources(
        for providers: [ProviderDescriptor],
        style: StatusBarDisplayStyle,
        providerSnapshots: [String: UsageSnapshot],
        codexActiveSnapshot: UsageSnapshot?,
        claudeDisplaySnapshot: UsageSnapshot?,
        thirdPartyBarPercentProvider: (String) -> Double?
    ) -> [StatusBarDisplaySource] {
        providers.map { provider in
            displaySource(
                for: provider,
                style: style,
                providerSnapshots: providerSnapshots,
                codexActiveSnapshot: codexActiveSnapshot,
                claudeDisplaySnapshot: claudeDisplaySnapshot,
                thirdPartyBarPercent: thirdPartyBarPercentProvider(provider.id)
            )
        }
    }

    static func displaySource(
        for provider: ProviderDescriptor,
        style: StatusBarDisplayStyle,
        providerSnapshots: [String: UsageSnapshot],
        codexActiveSnapshot: UsageSnapshot?,
        claudeDisplaySnapshot: UsageSnapshot?,
        thirdPartyBarPercent: Double?
    ) -> StatusBarDisplaySource {
        StatusBarDisplaySource(
            provider: provider,
            snapshot: resolvedSnapshot(
                for: provider,
                providerSnapshots: providerSnapshots,
                codexActiveSnapshot: codexActiveSnapshot,
                claudeDisplaySnapshot: claudeDisplaySnapshot
            ),
            thirdPartyBarPercent: resolvedThirdPartyBarPercent(
                for: provider,
                style: style,
                candidate: thirdPartyBarPercent
            )
        )
    }

    static func resolvedSnapshot(
        for provider: ProviderDescriptor,
        providerSnapshots: [String: UsageSnapshot],
        codexActiveSnapshot: UsageSnapshot?,
        claudeDisplaySnapshot: UsageSnapshot?
    ) -> UsageSnapshot? {
        if provider.type == .codex {
            if let codexActiveSnapshot,
               codexActiveSnapshot.rawMeta["codex.menuPlaceholder"] != "true" {
                return codexActiveSnapshot
            }
            return providerSnapshots[provider.id] ?? codexActiveSnapshot
        }
        if provider.type == .claude, provider.family == .official {
            return claudeDisplaySnapshot
        }
        return providerSnapshots[provider.id]
    }

    static func resolvedThirdPartyBarPercent(
        for provider: ProviderDescriptor,
        style: StatusBarDisplayStyle,
        candidate: Double?
    ) -> Double? {
        guard style == .barNamePercent,
              provider.family == .thirdParty,
              !provider.displaysUsedQuota else {
            return nil
        }
        return candidate
    }
}
