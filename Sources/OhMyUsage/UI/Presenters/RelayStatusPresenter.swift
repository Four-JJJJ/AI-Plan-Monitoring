import OhMyUsageDomain
import SwiftUI

struct RelayDisplayStatus {
    var text: String
    var color: Color
}

enum RelayStatusPresenter {
    static func providerSummaryStatus(
        snapshot: UsageSnapshot?,
        hasError: Bool,
        language: AppLanguage
    ) -> RelayDisplayStatus {
        if let snapshot, snapshot.valueFreshness == .cachedFallback {
            return cachedRelayStatus(fetchHealth: snapshot.fetchHealth, language: language)
        }

        if let snapshot, snapshot.valueFreshness == .empty {
            switch snapshot.fetchHealth {
            case .authExpired:
                return RelayDisplayStatus(text: localized("认证失效", "Auth expired", language), color: Color(hex: 0xD05757))
            case .endpointMisconfigured:
                return RelayDisplayStatus(text: localized("配置异常", "Config issue", language), color: Color(hex: 0xD05757))
            case .rateLimited:
                return RelayDisplayStatus(text: localized("接口限流", "Rate limited", language), color: Color(hex: 0xE88B2D))
            case .unreachable:
                return RelayDisplayStatus(text: Localizer.text(.statusDisconnected, language: language), color: Color(hex: 0xD05757))
            case .ok:
                break
            }
        }

        if hasError {
            return RelayDisplayStatus(text: Localizer.text(.statusDisconnected, language: language), color: Color(hex: 0xD05757))
        }

        guard let remaining = snapshot?.remaining else {
            return RelayDisplayStatus(text: Localizer.text(.statusTight, language: language), color: Color(hex: 0xE88B2D))
        }

        if remaining > 50 {
            return RelayDisplayStatus(text: Localizer.text(.statusSufficient, language: language), color: Color(hex: 0x69BD64))
        }
        if remaining > 0 {
            return RelayDisplayStatus(text: Localizer.text(.statusTight, language: language), color: Color(hex: 0xE88B2D))
        }
        return RelayDisplayStatus(text: Localizer.text(.statusExhausted, language: language), color: Color(hex: 0xD05757))
    }

    static func cachedRelayStatus(fetchHealth: FetchHealth, language: AppLanguage) -> RelayDisplayStatus {
        switch fetchHealth {
        case .authExpired:
            return RelayDisplayStatus(text: localized("认证失效(缓存)", "Auth expired (cached)", language), color: Color(hex: 0xD05757))
        case .endpointMisconfigured:
            return RelayDisplayStatus(text: localized("配置异常(缓存)", "Config issue (cached)", language), color: Color(hex: 0xD05757))
        case .rateLimited:
            return RelayDisplayStatus(text: localized("限流回退", "Rate limited (cached)", language), color: Color(hex: 0xE88B2D))
        case .unreachable, .ok:
            return RelayDisplayStatus(text: localized("缓存回退", "Cached fallback", language), color: Color(hex: 0xE88B2D))
        }
    }

    static func fetchHealthDisplayStatus(
        health: FetchHealth?,
        hasError: Bool,
        language: AppLanguage
    ) -> RelayDisplayStatus {
        if let health {
            return RelayDisplayStatus(text: fetchHealthLabel(health, language: language), color: fetchHealthColor(health))
        }
        if hasError {
            return RelayDisplayStatus(text: fetchHealthLabel(.unreachable, language: language), color: fetchHealthColor(.unreachable))
        }
        return RelayDisplayStatus(text: fetchHealthLabel(.ok, language: language), color: fetchHealthColor(.ok))
    }

    static func fetchHealthLabel(_ health: FetchHealth, language: AppLanguage) -> String {
        switch (language, health) {
        case (.zhHans, .ok):
            return "接口正常"
        case (.zhHans, .authExpired):
            return "认证失效"
        case (.zhHans, .rateLimited):
            return "接口限流"
        case (.zhHans, .endpointMisconfigured):
            return "接口配置异常"
        case (.zhHans, .unreachable):
            return "站点不可达"
        case (.en, .ok):
            return "Live"
        case (.en, .authExpired):
            return "Auth expired"
        case (.en, .rateLimited):
            return "Rate limited"
        case (.en, .endpointMisconfigured):
            return "Config issue"
        case (.en, .unreachable):
            return "Unreachable"
        }
    }

    static func fetchHealthColor(_ health: FetchHealth) -> Color {
        switch health {
        case .ok:
            return .green
        case .rateLimited:
            return Color(hex: 0xD87E3E)
        case .authExpired, .endpointMisconfigured, .unreachable:
            return Color(hex: 0xD83E3E)
        }
    }

    static func valueFreshnessLabel(_ freshness: ValueFreshness, language: AppLanguage) -> String {
        switch (language, freshness) {
        case (.zhHans, .live):
            return "实时值"
        case (.zhHans, .cachedFallback):
            return "缓存回退"
        case (.zhHans, .empty):
            return "暂无可用值"
        case (.en, .live):
            return "Live"
        case (.en, .cachedFallback):
            return "Cached fallback"
        case (.en, .empty):
            return "No usable value"
        }
    }

    private static func localized(_ zhHans: String, _ en: String, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            return zhHans
        case .en:
            return en
        }
    }
}
