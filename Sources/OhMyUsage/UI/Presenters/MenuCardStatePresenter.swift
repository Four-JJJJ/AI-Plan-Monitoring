import OhMyUsageDomain
import OhMyUsageApplication
import Foundation

struct MenuCardVisualPresentation: Equatable {
    var status: MenuCardStatusPresentation
    var errorText: String?
    var isDisconnected: Bool
    var showsErrorHighlight: Bool
}

struct MenuAmountCardPresentation: Equatable {
    var visual: MenuCardVisualPresentation
    var amountText: String
    var secondaryText: String?
    var balanceLabel: String
}

struct MenuSlotActionPresentation: Equatable {
    enum InfoTone: Equatable {
        case normal
        case error
    }

    var showsLeadingAccent: Bool
    var actionLabel: String?
    var actionDisabled: Bool
    var infoText: String?
    var infoTone: InfoTone
}

enum MenuCardStatePresenter {
    static func percentageVisualPresentation(
        snapshot: UsageSnapshot?,
        errorText: String?,
        healthPercents: [Double?],
        language: AppLanguage,
        tightText: String,
        sufficientText: String,
        exhaustedText: String,
        disconnectedText: String
    ) -> MenuCardVisualPresentation {
        let stale = snapshot?.valueFreshness == .cachedFallback
        let disconnected = errorText != nil && !stale

        return MenuCardVisualPresentation(
            status: MenuCardStatusPresenter.percentageStatus(
                healthPercents: healthPercents,
                snapshot: snapshot,
                disconnected: disconnected,
                language: language,
                tightText: tightText,
                sufficientText: sufficientText,
                exhaustedText: exhaustedText,
                disconnectedText: disconnectedText
            ),
            errorText: errorText,
            isDisconnected: disconnected,
            showsErrorHighlight: disconnected || stale || (snapshot?.valueFreshness == .empty && snapshot?.fetchHealth != .ok)
        )
    }

    static func amountPresentation(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        errorText: String?,
        language: AppLanguage,
        secondaryText: String?,
        usedLabel: String,
        balanceLabel: String,
        tightText: String,
        sufficientText: String,
        exhaustedText: String,
        disconnectedText: String
    ) -> MenuAmountCardPresentation {
        let stale = snapshot?.valueFreshness == .cachedFallback
        let disconnected = errorText != nil && !stale
        let visual = MenuCardVisualPresentation(
            status: MenuCardStatusPresenter.amountStatus(
                remaining: snapshot?.remaining,
                snapshot: snapshot,
                disconnected: disconnected,
                language: language,
                tightText: tightText,
                sufficientText: sufficientText,
                exhaustedText: exhaustedText,
                disconnectedText: disconnectedText
            ),
            errorText: errorText,
            isDisconnected: disconnected || stale,
            showsErrorHighlight: disconnected || (snapshot?.valueFreshness == .empty && snapshot?.fetchHealth != .ok)
        )

        return MenuAmountCardPresentation(
            visual: visual,
            amountText: (disconnected || stale) ? "-" : formattedBalanceNumber(displayedAmountValue(provider: provider, snapshot: snapshot)),
            secondaryText: (disconnected || stale) ? nil : secondaryText,
            balanceLabel: provider.displaysUsedQuota ? usedLabel : balanceLabel
        )
    }

    static func slotActionPresentation(
        isActive: Bool,
        canSwitch: Bool,
        isSwitching: Bool,
        actionLabel: String,
        infoText: String?,
        infoIsError: Bool
    ) -> MenuSlotActionPresentation {
        let showsSwitchAction = !isActive && canSwitch
        return MenuSlotActionPresentation(
            showsLeadingAccent: isActive,
            actionLabel: showsSwitchAction ? actionLabel : nil,
            actionDisabled: showsSwitchAction ? isSwitching : false,
            infoText: infoText,
            infoTone: infoIsError ? .error : .normal
        )
    }

    private static func displayedAmountValue(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> Double? {
        guard let snapshot else { return nil }
        if provider.displaysUsedQuota, let used = snapshot.used {
            return used
        }
        return snapshot.remaining
    }

    private static func formattedBalanceNumber(_ value: Double?) -> String {
        guard let value else { return "-" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
