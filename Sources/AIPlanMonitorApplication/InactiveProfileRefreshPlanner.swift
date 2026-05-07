import Foundation

package struct InactiveProfileRefreshSelection<SlotID: Hashable & Sendable>: Equatable, Sendable {
    package var slotID: SlotID
    package var nextCursor: Int

    package init(slotID: SlotID, nextCursor: Int) {
        self.slotID = slotID
        self.nextCursor = nextCursor
    }
}

package struct InactiveProfileRefreshRetryState<SlotID: Hashable & Sendable>: Equatable, Sendable {
    package private(set) var failureCounts: [SlotID: Int] = [:]
    package private(set) var retryNotBefore: [SlotID: Date] = [:]

    package init() {}

    package mutating func markSuccess(slotID: SlotID) {
        failureCounts.removeValue(forKey: slotID)
        retryNotBefore.removeValue(forKey: slotID)
    }

    package mutating func markFailure(slotID: SlotID, baseInterval: Int, now: Date) {
        let nextFailures = failureCounts[slotID, default: 0] + 1
        failureCounts[slotID] = nextFailures
        retryNotBefore[slotID] = InactiveProfileRefreshPlanner.nextRetryAt(
            now: now,
            baseInterval: baseInterval,
            consecutiveFailures: nextFailures
        )
    }

    package mutating func remove(slotID: SlotID) {
        failureCounts.removeValue(forKey: slotID)
        retryNotBefore.removeValue(forKey: slotID)
    }

    package mutating func prune(keeping slotIDs: Set<SlotID>) {
        failureCounts = failureCounts.filter { slotIDs.contains($0.key) }
        retryNotBefore = retryNotBefore.filter { slotIDs.contains($0.key) }
    }
}

package enum InactiveProfileRefreshPlanner {
    package static func shouldAttemptProviderRefresh(
        lastAttemptAt: Date?,
        minimumInterval: TimeInterval,
        now: Date
    ) -> Bool {
        guard let lastAttemptAt else { return true }
        return now.timeIntervalSince(lastAttemptAt) >= max(1, minimumInterval)
    }

    package static func selectNextSlot<SlotID: Hashable & Sendable>(
        orderedSlotIDs: [SlotID],
        activeSlotIDs: Set<SlotID>,
        inFlightSlotIDs: Set<SlotID>,
        retryNotBefore: [SlotID: Date],
        cursor: Int,
        now: Date
    ) -> InactiveProfileRefreshSelection<SlotID>? {
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

    package static func nextRetryAt(
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
