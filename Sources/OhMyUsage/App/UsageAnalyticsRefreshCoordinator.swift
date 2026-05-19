import Foundation

@MainActor
final class UsageAnalyticsRefreshCoordinator {
    typealias SourceFingerprintLoader = @Sendable (_ claudeAllConfigDirs: [String]) -> UsageAnalyticsSourceFingerprint
    typealias SnapshotLoader = @Sendable (
        _ filter: UsageAnalyticsFilter,
        _ claudeAllConfigDirs: [String]
    ) -> UsageAnalyticsSnapshot

    private let sourceFingerprintLoader: SourceFingerprintLoader
    private let snapshotLoader: SnapshotLoader
    private let cacheStore: UsageAnalyticsSnapshotCacheStore
    private let nowProvider: () -> Date
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    init(
        repository: UsageAnalyticsRepository = UsageAnalyticsRepository(),
        cacheStore: UsageAnalyticsSnapshotCacheStore = UsageAnalyticsSnapshotCacheStore(),
        nowProvider: @escaping () -> Date = Date.init,
        sourceFingerprintLoader: SourceFingerprintLoader? = nil,
        snapshotLoader: SnapshotLoader? = nil
    ) {
        self.cacheStore = cacheStore
        self.nowProvider = nowProvider
        self.sourceFingerprintLoader = sourceFingerprintLoader ?? { claudeAllConfigDirs in
            repository.sourceFingerprint(claudeAllConfigDirs: claudeAllConfigDirs)
        }
        self.snapshotLoader = snapshotLoader ?? { filter, claudeAllConfigDirs in
            repository.snapshot(
                filter: filter,
                claudeAllConfigDirs: claudeAllConfigDirs
            )
        }
    }

    func refreshUsageAnalyticsIfNeeded(
        filter: UsageAnalyticsFilter,
        currentSnapshotFilter: UsageAnalyticsFilter,
        claudeAllConfigDirs: [String],
        force: Bool = false,
        onSnapshotChange: @escaping @MainActor (UsageAnalyticsSnapshot) -> Void,
        onLoadingChange: @escaping @MainActor (Bool) -> Void
    ) {
        let cachedEntry = cacheStore.entry(for: filter)
        let hasCachedSnapshot = cachedEntry?.snapshot != nil

        if let snapshot = cachedEntry?.snapshot {
            onSnapshotChange(snapshot)
        } else if currentSnapshotFilter != filter {
            onSnapshotChange(UsageAnalyticsSnapshot.empty(filter: filter))
        }

        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let cacheStore = cacheStore
        let sourceFingerprintLoader = sourceFingerprintLoader
        let snapshotLoader = snapshotLoader
        let nowProvider = nowProvider
        onLoadingChange(force || !hasCachedSnapshot)

        refreshTask = Task { @MainActor [weak self] in
            let fingerprint = await Task.detached(priority: .utility) {
                sourceFingerprintLoader(claudeAllConfigDirs)
            }.value

            guard !Task.isCancelled else { return }
            guard let self, generation == self.refreshGeneration else { return }

            let validationDate = nowProvider()
            if !force,
               let entry = cacheStore.entry(for: filter),
               entry.sourceFingerprint == fingerprint,
               cacheStore.isEntryTemporallyFresh(
                   for: filter,
                   now: validationDate,
                   calendar: .current
               ) {
                cacheStore.markValidated(
                    filter: filter,
                    sourceFingerprint: fingerprint,
                    at: validationDate
                )
                onLoadingChange(false)
                refreshTask = nil
                return
            }

            if !hasCachedSnapshot {
                onLoadingChange(true)
            }

            let snapshot = await Task.detached(priority: .utility) {
                snapshotLoader(filter, claudeAllConfigDirs)
            }.value

            guard !Task.isCancelled else { return }
            guard generation == self.refreshGeneration else { return }

            cacheStore.save(snapshot: snapshot, sourceFingerprint: fingerprint)
            onSnapshotChange(snapshot)
            onLoadingChange(false)
            refreshTask = nil
        }
    }
}
