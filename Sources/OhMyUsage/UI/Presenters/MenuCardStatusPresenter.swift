import OhMyUsageDomain
import OhMyUsageApplication
import Foundation

struct MenuCardStatusPresentation: Equatable {
    enum Tone: Equatable {
        case normal
        case warning
        case error
    }

    var text: String
    var tone: Tone
}

enum MenuCardStatusPresenter {
    static func planType(for provider: ProviderDescriptor, snapshot: UsageSnapshot?) -> String? {
        if provider.family == .official {
            let showsPlanType = provider.officialConfig?.showPlanTypeInMenuBar
                ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type).showPlanTypeInMenuBar
            guard showsPlanType else { return nil }

            return PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: provider.type,
                extrasPlanType: snapshot?.extras["planType"],
                rawPlanType: snapshot?.rawMeta["planType"]
            )
        }

        return PlanTypeDisplayFormatter.normalizedPlanType(
            snapshot?.extras["planType"],
            providerType: provider.type
        ) ?? PlanTypeDisplayFormatter.normalizedPlanType(
            snapshot?.rawMeta["planType"],
            providerType: provider.type
        )
    }

    static func percentageStatus(
        healthPercents: [Double?],
        snapshot: UsageSnapshot?,
        disconnected: Bool,
        language: AppLanguage,
        tightText: String,
        sufficientText: String,
        exhaustedText: String,
        disconnectedText: String
    ) -> MenuCardStatusPresentation {
        if let snapshot, snapshot.valueFreshness == .cachedFallback {
            return cachedRelayStatus(fetchHealth: snapshot.fetchHealth, language: language)
        }

        if let snapshot, snapshot.valueFreshness == .empty {
            switch snapshot.fetchHealth {
            case .authExpired, .endpointMisconfigured, .rateLimited, .unreachable:
                return failureStatus(language: language)
            case .ok:
                break
            }
        }

        if disconnected {
            return failureStatus(language: language)
        }

        let availableHealthPercents = healthPercents
            .compactMap { $0.map { Int($0.rounded()) } }
        guard let displayedMinimum = availableHealthPercents.min() else {
            return MenuCardStatusPresentation(text: tightText, tone: .warning)
        }
        if displayedMinimum <= 0 {
            return MenuCardStatusPresentation(text: exhaustedText, tone: .error)
        }
        if displayedMinimum > 30 {
            return MenuCardStatusPresentation(text: sufficientText, tone: .normal)
        }
        if displayedMinimum < 10 {
            return MenuCardStatusPresentation(text: tightText, tone: .error)
        }
        return MenuCardStatusPresentation(text: tightText, tone: .warning)
    }

    static func amountStatus(
        remaining: Double?,
        snapshot: UsageSnapshot?,
        disconnected: Bool,
        language: AppLanguage,
        tightText: String,
        sufficientText: String,
        exhaustedText: String,
        disconnectedText: String
    ) -> MenuCardStatusPresentation {
        if let snapshot, snapshot.valueFreshness == .cachedFallback {
            return cachedRelayStatus(fetchHealth: snapshot.fetchHealth, language: language)
        }

        if let snapshot, snapshot.valueFreshness == .empty {
            switch snapshot.fetchHealth {
            case .authExpired, .endpointMisconfigured, .rateLimited, .unreachable:
                return failureStatus(language: language)
            case .ok:
                break
            }
        }

        if disconnected {
            return failureStatus(language: language)
        }

        guard let remaining else {
            return MenuCardStatusPresentation(text: tightText, tone: .warning)
        }
        if remaining > 50 {
            return MenuCardStatusPresentation(text: sufficientText, tone: .normal)
        }
        if remaining > 0 {
            return MenuCardStatusPresentation(text: tightText, tone: .warning)
        }
        return MenuCardStatusPresentation(text: exhaustedText, tone: .error)
    }

    static func cachedRelayStatus(fetchHealth: FetchHealth, language: AppLanguage) -> MenuCardStatusPresentation {
        failureStatus(language: language)
    }

    static func cachedFetchHealthStatusText(_ health: FetchHealth, language: AppLanguage) -> String {
        failureText(language: language)
    }

    private static func failureStatus(language: AppLanguage) -> MenuCardStatusPresentation {
        MenuCardStatusPresentation(text: failureText(language: language), tone: .error)
    }

    private static func failureText(language: AppLanguage) -> String {
        language == .zhHans ? "故障" : "Failure"
    }
}
