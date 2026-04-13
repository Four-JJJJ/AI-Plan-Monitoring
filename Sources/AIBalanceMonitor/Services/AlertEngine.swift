import Foundation

struct AlertEngine {
    static func shouldAlertLowRemaining(snapshot: UsageSnapshot, rule: AlertRule) -> Bool {
        guard let remaining = snapshot.remaining else {
            return false
        }
        return remaining <= rule.lowRemaining
    }

    static func lowQuotaWindows(snapshot: UsageSnapshot, rule: AlertRule) -> [UsageQuotaWindow] {
        snapshot.quotaWindows.filter { $0.remainingPercent <= rule.lowRemaining }
    }

    static func shouldAlertFailures(consecutiveFailures: Int, rule: AlertRule) -> Bool {
        consecutiveFailures >= rule.maxConsecutiveFailures
    }

    static func isAuthError(_ error: Error) -> Bool {
        if case ProviderError.unauthorized = error {
            return true
        }
        if case ProviderError.unauthorizedDetail = error {
            return true
        }
        return false
    }
}
