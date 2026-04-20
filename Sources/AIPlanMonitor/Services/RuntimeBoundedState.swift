import Foundation

enum RuntimeBoundedState {
    static func boundedSnapshotNote(
        _ note: String,
        maxLength: Int = RuntimeDiagnosticsLimits.snapshotNoteMaxLength
    ) -> String {
        let normalized = dedupedNoteSegments(from: note).joined(separator: " | ")
        return trimmedToMaxLength(normalized, maxLength: maxLength)
    }

    static func appendSnapshotNote(
        existing: String,
        appending segment: String,
        maxLength: Int = RuntimeDiagnosticsLimits.snapshotNoteMaxLength
    ) -> String {
        let trimmedSegment = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSegment.isEmpty else {
            return boundedSnapshotNote(existing, maxLength: maxLength)
        }

        var segments = dedupedNoteSegments(from: existing)
        let existingKeys = Set(segments.map { noteDedupKey($0) })
        if !existingKeys.contains(noteDedupKey(trimmedSegment)) {
            segments.append(trimmedSegment)
        }
        let joined = segments.joined(separator: " | ")
        return trimmedToMaxLength(joined, maxLength: maxLength)
    }

    static func slimmedLocalUsageSummaryForCache(
        _ summary: LocalUsageSummary,
        modelBreakdownLimit: Int = RuntimeDiagnosticsLimits.localUsageTrendModelBreakdownCacheEntries
    ) -> LocalUsageSummary {
        LocalUsageSummary(
            today: slimmedPeriod(summary.today, modelBreakdownLimit: modelBreakdownLimit),
            yesterday: slimmedPeriod(summary.yesterday, modelBreakdownLimit: modelBreakdownLimit),
            last30Days: slimmedPeriod(summary.last30Days, modelBreakdownLimit: modelBreakdownLimit),
            hourly24: summary.hourly24,
            daily7: summary.daily7,
            sourcePath: summary.sourcePath,
            generatedAt: summary.generatedAt,
            diagnostics: summary.diagnostics,
            isApproximateFallback: summary.isApproximateFallback
        )
    }

    @discardableResult
    static func pruneLocalUsageTrendCaches(
        summaries: inout [String: LocalUsageSummary],
        errors: inout [String: String],
        queryLastRefreshedAt: inout [String: Date],
        loadingQueryKeys: inout Set<String>,
        now: Date,
        maxEntries: Int = RuntimeDiagnosticsLimits.localUsageTrendCacheMaxEntries,
        ttl: TimeInterval = RuntimeDiagnosticsLimits.localUsageTrendCacheEntryTTL
    ) -> Set<String> {
        let safeMaxEntries = max(1, maxEntries)
        let safeTTL = max(30, ttl)
        let expiryCutoff = now.addingTimeInterval(-safeTTL)
        var removedKeys: Set<String> = []

        for (key, refreshedAt) in queryLastRefreshedAt where refreshedAt < expiryCutoff {
            removedKeys.insert(key)
        }

        if !removedKeys.isEmpty {
            removeKeys(
                removedKeys,
                summaries: &summaries,
                errors: &errors,
                queryLastRefreshedAt: &queryLastRefreshedAt,
                loadingQueryKeys: &loadingQueryKeys
            )
        }

        if queryLastRefreshedAt.count > safeMaxEntries {
            let sortedByFreshness = queryLastRefreshedAt.sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key < rhs.key
            }
            let keepKeys = Set(sortedByFreshness.prefix(safeMaxEntries).map(\.key))
            let overflowKeys = Set(queryLastRefreshedAt.keys).subtracting(keepKeys)
            if !overflowKeys.isEmpty {
                removedKeys.formUnion(overflowKeys)
                removeKeys(
                    overflowKeys,
                    summaries: &summaries,
                    errors: &errors,
                    queryLastRefreshedAt: &queryLastRefreshedAt,
                    loadingQueryKeys: &loadingQueryKeys
                )
            }
        }

        let knownKeys = Set(queryLastRefreshedAt.keys)
        summaries = summaries.filter { knownKeys.contains($0.key) }
        errors = errors.filter { knownKeys.contains($0.key) }
        loadingQueryKeys = loadingQueryKeys.intersection(knownKeys)

        return removedKeys
    }

    private static func dedupedNoteSegments(from raw: String) -> [String] {
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else { return [] }

        let sourceSegments: [String]
        if trimmedRaw.contains("|") {
            sourceSegments = trimmedRaw
                .split(separator: "|", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            sourceSegments = [trimmedRaw]
        }

        var output: [String] = []
        var seen: Set<String> = []
        output.reserveCapacity(sourceSegments.count)
        for segment in sourceSegments where !segment.isEmpty {
            let key = noteDedupKey(segment)
            if seen.insert(key).inserted {
                output.append(segment)
            }
        }
        return output
    }

    private static func noteDedupKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func trimmedToMaxLength(_ value: String, maxLength: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = max(64, maxLength)
        guard trimmed.count > limit else { return trimmed }

        let suffix = String(trimmed.suffix(limit))
        let cleaned = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "| ").union(.whitespacesAndNewlines))
        return cleaned.isEmpty ? suffix : cleaned
    }

    private static func slimmedPeriod(
        _ value: LocalUsagePeriodSummary,
        modelBreakdownLimit: Int
    ) -> LocalUsagePeriodSummary {
        if modelBreakdownLimit <= 0 {
            return LocalUsagePeriodSummary(
                totalTokens: value.totalTokens,
                responses: value.responses,
                byModel: []
            )
        }
        return LocalUsagePeriodSummary(
            totalTokens: value.totalTokens,
            responses: value.responses,
            byModel: Array(value.byModel.prefix(modelBreakdownLimit))
        )
    }

    private static func removeKeys(
        _ keys: Set<String>,
        summaries: inout [String: LocalUsageSummary],
        errors: inout [String: String],
        queryLastRefreshedAt: inout [String: Date],
        loadingQueryKeys: inout Set<String>
    ) {
        guard !keys.isEmpty else { return }
        for key in keys {
            summaries.removeValue(forKey: key)
            errors.removeValue(forKey: key)
            queryLastRefreshedAt.removeValue(forKey: key)
            loadingQueryKeys.remove(key)
        }
    }
}
