import Foundation
import OhMyUsageDomain

enum OfficialMonitoringHealthStatus: Equatable {
    case unknown
    case authError
    case configError
    case rateLimited
    case disconnected
    case sufficient
    case tight
    case exhausted
}

enum SettingsQuotaPresenter {
    nonisolated static func resolvedOfficialMonitoringProvider(
        type: ProviderType,
        providers: [ProviderDescriptor]
    ) -> ProviderDescriptor {
        if let configured = providers.first(where: { $0.family == .official && $0.type == type }) {
            return configured
        }

        return ProviderDescriptor(
            id: "\(type.rawValue)-official",
            name: type.rawValue,
            family: .official,
            type: type,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            officialConfig: ProviderDescriptor.defaultOfficialConfig(type: type)
        )
    }

    nonisolated static func quotaMetricPercents(
        for window: UsageQuotaWindow,
        displaysUsedQuota: Bool
    ) -> (displayPercent: Double, healthPercent: Double) {
        let healthPercent = max(0, min(100, window.remainingPercent))
        let displayPercent = displaysUsedQuota
            ? max(0, min(100, window.usedPercent))
            : healthPercent
        return (displayPercent, healthPercent)
    }

    nonisolated static func officialMonitoringHealthStatus(
        snapshot: UsageSnapshot?,
        healthPercents: [Double]
    ) -> OfficialMonitoringHealthStatus {
        guard let snapshot else {
            return .unknown
        }

        if snapshot.valueFreshness == .empty {
            switch snapshot.fetchHealth {
            case .authExpired:
                return .authError
            case .endpointMisconfigured:
                return .configError
            case .rateLimited:
                return .rateLimited
            case .unreachable:
                return .disconnected
            case .ok:
                return .tight
            }
        }

        guard let minimum = healthPercents.min() else {
            return .tight
        }
        if minimum > 30 {
            return .sufficient
        }
        if minimum > 10 {
            return .tight
        }
        return .exhausted
    }
}

enum QuotaBlockagePresenter {
    nonisolated static func normalizedKind(
        for window: UsageQuotaWindow,
        provider: ProviderDescriptor
    ) -> UsageQuotaKind {
        let normalizedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if provider.type == .kimi, window.kind == .custom, normalizedTitle == "overall" {
            return .weekly
        }
        return window.kind
    }

    nonisolated static func isBlockedByDepletedWeeklyQuota(
        currentKind: UsageQuotaKind?,
        currentRemainingPercent: Double?,
        currentIsAvailable: Bool = true,
        candidateWindows: [(kind: UsageQuotaKind?, remainingPercent: Double?, isAvailable: Bool)]
    ) -> Bool {
        guard currentIsAvailable,
              currentKind == .session,
              (currentRemainingPercent ?? 0) > 0 else {
            return false
        }

        return candidateWindows.contains { candidate in
            candidate.isAvailable
                && candidate.kind == .weekly
                && (candidate.remainingPercent ?? 100) <= 0
        }
    }

    nonisolated static func isBlockedByDepletedWeeklyQuota(
        window: UsageQuotaWindow,
        in windows: [UsageQuotaWindow],
        provider: ProviderDescriptor
    ) -> Bool {
        isBlockedByDepletedWeeklyQuota(
            currentKind: normalizedKind(for: window, provider: provider),
            currentRemainingPercent: window.remainingPercent,
            candidateWindows: windows.map {
                (
                    kind: normalizedKind(for: $0, provider: provider),
                    remainingPercent: $0.remainingPercent,
                    isAvailable: true
                )
            }
        )
    }
}
