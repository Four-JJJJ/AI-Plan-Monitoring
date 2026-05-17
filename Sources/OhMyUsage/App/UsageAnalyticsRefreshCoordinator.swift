import Foundation

@MainActor
final class UsageAnalyticsRefreshCoordinator {
    private let repository: UsageAnalyticsRepository
    private let cacheStore: UsageAnalyticsSnapshotCacheStore
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    init(
        repository: UsageAnalyticsRepository = UsageAnalyticsRepository(),
        cacheStore: UsageAnalyticsSnapshotCacheStore = UsageAnalyticsSnapshotCacheStore()
    ) {
        self.repository = repository
        self.cacheStore = cacheStore
    }

    func refreshUsageAnalyticsIfNeeded(
        filter: UsageAnalyticsFilter,
        currentSnapshotFilter: UsageAnalyticsFilter,
        claudeAllConfigDirs: [String],
        force: Bool = false,
        onSnapshotChange: @escaping @MainActor (UsageAnalyticsSnapshot) -> Void,
        onLoadingChange: @escaping @MainActor (Bool) -> Void
    ) {
        let now = Date()
        let cachedEntry = cacheStore.entry(for: filter)
        let hasCachedSnapshot = cachedEntry?.snapshot != nil

        if let snapshot = cachedEntry?.snapshot {
            onSnapshotChange(snapshot)
        } else if currentSnapshotFilter != filter {
            onSnapshotChange(UsageAnalyticsSnapshot.empty(filter: filter))
        }

        if !force,
           hasCachedSnapshot,
           cacheStore.isEntryTemporallyFresh(
               for: filter,
               now: now,
               calendar: .current
           ),
           !cacheStore.shouldProbeFingerprint(for: filter, now: now) {
            onLoadingChange(false)
            return
        }

        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let repository = repository
        let cacheStore = cacheStore
        onLoadingChange(force || !hasCachedSnapshot)

        refreshTask = Task { @MainActor [weak self] in
            let fingerprint = await Task.detached(priority: .utility) {
                repository.sourceFingerprint(claudeAllConfigDirs: claudeAllConfigDirs)
            }.value

            guard !Task.isCancelled else { return }
            guard let self, generation == self.refreshGeneration else { return }

            let validationDate = Date()
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
                self.repository.snapshot(
                    filter: filter,
                    claudeAllConfigDirs: claudeAllConfigDirs
                )
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
