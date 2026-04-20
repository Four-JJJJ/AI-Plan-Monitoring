import Foundation

struct ThirdPartyBalanceBaselineTracker {
    struct Entry {
        var baseline: Double
        var lastRemaining: Double
        var updatedAt: Date
    }

    private var entries: [String: Entry] = [:]

    @discardableResult
    mutating func record(remaining: Double?, for providerID: String, at timestamp: Date = Date()) -> Double? {
        guard !providerID.isEmpty,
              let remaining,
              remaining.isFinite,
              remaining >= 0 else {
            return nil
        }

        if var entry = entries[providerID] {
            if remaining > entry.lastRemaining {
                entry.baseline = remaining
            }
            entry.lastRemaining = remaining
            entry.updatedAt = timestamp
            entries[providerID] = entry
            return Self.normalizedPercent(remaining: remaining, baseline: entry.baseline)
        }

        entries[providerID] = Entry(
            baseline: remaining,
            lastRemaining: remaining,
            updatedAt: timestamp
        )
        return 100
    }

    func percent(for providerID: String) -> Double? {
        guard let entry = entries[providerID] else { return nil }
        return Self.normalizedPercent(remaining: entry.lastRemaining, baseline: entry.baseline)
    }

    mutating func remove(providerID: String) {
        entries.removeValue(forKey: providerID)
    }

    mutating func removeAll() {
        entries.removeAll()
    }

    mutating func prune(keepingProviderIDs: Set<String>, maxEntries: Int) {
        entries = entries.filter { keepingProviderIDs.contains($0.key) }

        let safeMaxEntries = max(1, maxEntries)
        guard entries.count > safeMaxEntries else { return }

        let keepKeys = entries
            .sorted { lhs, rhs in
                if lhs.value.updatedAt != rhs.value.updatedAt {
                    return lhs.value.updatedAt > rhs.value.updatedAt
                }
                return lhs.key < rhs.key
            }
            .prefix(safeMaxEntries)
            .map(\.key)
        let keepSet = Set(keepKeys)
        entries = entries.filter { keepSet.contains($0.key) }
    }

    var entryCount: Int {
        entries.count
    }

    func contains(providerID: String) -> Bool {
        entries[providerID] != nil
    }

    private static func normalizedPercent(remaining: Double, baseline: Double) -> Double {
        guard baseline > 0 else { return 100 }
        let ratio = (remaining / baseline) * 100
        guard ratio.isFinite else { return 100 }
        return min(max(ratio, 0), 100)
    }
}
