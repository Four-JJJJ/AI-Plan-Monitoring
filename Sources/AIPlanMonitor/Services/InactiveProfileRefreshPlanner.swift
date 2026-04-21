import Foundation

struct InactiveProfileRefreshSelection: Equatable {
    var slotID: CodexSlotID
    var nextCursor: Int
}

struct InactiveProfileRefreshRetryState: Equatable {
    private(set) var failureCounts: [CodexSlotID: Int] = [:]
    private(set) var retryNotBefore: [CodexSlotID: Date] = [:]

    mutating func markSuccess(slotID: CodexSlotID) {
        failureCounts.removeValue(forKey: slotID)
        retryNotBefore.removeValue(forKey: slotID)
    }

    mutating func markFailure(slotID: CodexSlotID, baseInterval: Int, now: Date) {
        let nextFailures = failureCounts[slotID, default: 0] + 1
        failureCounts[slotID] = nextFailures
        retryNotBefore[slotID] = InactiveProfileRefreshPlanner.nextRetryAt(
            now: now,
            baseInterval: baseInterval,
            consecutiveFailures: nextFailures
        )
    }

    mutating func remove(slotID: CodexSlotID) {
        failureCounts.removeValue(forKey: slotID)
        retryNotBefore.removeValue(forKey: slotID)
    }

    mutating func prune(keeping slotIDs: Set<CodexSlotID>) {
        failureCounts = failureCounts.filter { slotIDs.contains($0.key) }
        retryNotBefore = retryNotBefore.filter { slotIDs.contains($0.key) }
    }
}

enum InactiveProfileRefreshPlanner {
    static func shouldAttemptProviderRefresh(
        lastAttemptAt: Date?,
        minimumInterval: TimeInterval,
        now: Date
    ) -> Bool {
        guard let lastAttemptAt else { return true }
        return now.timeIntervalSince(lastAttemptAt) >= max(1, minimumInterval)
    }

    static func selectNextSlot(
        orderedSlotIDs: [CodexSlotID],
        activeSlotIDs: Set<CodexSlotID>,
        inFlightSlotIDs: Set<CodexSlotID>,
        retryNotBefore: [CodexSlotID: Date],
        cursor: Int,
        now: Date
    ) -> InactiveProfileRefreshSelection? {
        guard !orderedSlotIDs.isEmpty else { return nil }
        let count = orderedSlotIDs.count
        let normalizedCursor = ((cursor % count) + count) % count

        for offset in 0..<count {
            let index = (normalizedCursor + offset) % count
            let slotID = orderedSlotIDs[index]
            if activeSlotIDs.contains(slotID) {
                continue
            }
            if inFlightSlotIDs.contains(slotID) {
                continue
            }
            if let notBefore = retryNotBefore[slotID], notBefore > now {
                continue
            }
            return InactiveProfileRefreshSelection(
                slotID: slotID,
                nextCursor: (index + 1) % count
            )
        }
        return nil
    }

    static func nextRetryAt(
        now: Date,
        baseInterval: Int,
        consecutiveFailures: Int
    ) -> Date {
        let delay = BackoffPolicy.delaySeconds(
            baseInterval: max(1, baseInterval),
            consecutiveFailures: consecutiveFailures
        )
        return now.addingTimeInterval(TimeInterval(max(1, delay)))
    }
}
