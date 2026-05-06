import Foundation

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
