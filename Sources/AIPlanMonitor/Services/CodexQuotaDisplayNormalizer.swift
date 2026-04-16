import Foundation

enum CodexQuotaDisplayNormalizer {
    private static let sessionCycle: TimeInterval = 5 * 60 * 60
    private static let weeklyCycle: TimeInterval = 7 * 24 * 60 * 60

    static func normalize(snapshot: UsageSnapshot, isActive: Bool, now: Date = Date()) -> UsageSnapshot {
        guard !isActive, !snapshot.quotaWindows.isEmpty else {
            return snapshot
        }

        var copy = snapshot
        copy.quotaWindows = snapshot.quotaWindows.map { normalize(window: $0, now: now) }
        copy.remaining = copy.quotaWindows.map(\.remainingPercent).min()
        if let sessionWindow = copy.quotaWindows.first(where: { $0.kind == .session }) {
            copy.used = sessionWindow.usedPercent
        }
        return copy
    }

    private static func normalize(window: UsageQuotaWindow, now: Date) -> UsageQuotaWindow {
        guard let resetAt = window.resetAt,
              let cycle = cycleDuration(for: window.kind),
              resetAt <= now else {
            return window
        }

        var nextReset = resetAt
        while nextReset <= now {
            nextReset.addTimeInterval(cycle)
        }

        var copy = window
        copy.remainingPercent = 100
        copy.usedPercent = 0
        copy.resetAt = nextReset
        return copy
    }

    private static func cycleDuration(for kind: UsageQuotaKind) -> TimeInterval? {
        switch kind {
        case .session:
            return sessionCycle
        case .weekly:
            return weeklyCycle
        default:
            return nil
        }
    }
}
