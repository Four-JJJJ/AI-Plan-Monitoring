import Foundation

struct LocalUsageHistoryQuery: Codable, Equatable, Hashable, Sendable {
    var providerType: ProviderType
    var providerID: String
    var scope: LocalUsageTrendScope
    var identityKey: String

    init(
        providerType: ProviderType,
        providerID: String,
        scope: LocalUsageTrendScope,
        identityKey: String
    ) {
        self.providerType = providerType
        self.providerID = providerID
        self.scope = scope
        self.identityKey = identityKey
    }
}

struct LocalUsageSourceFingerprint: Codable, Equatable, Sendable {
    var roots: [String]
    var fileCount: Int
    var totalSize: UInt64
    var latestModificationTime: Date?
}

struct LocalUsageHistoryEntry: Codable, Equatable, Sendable {
    var query: LocalUsageHistoryQuery
    var summary: LocalUsageSummary?
    var refreshedAt: Date
    var sourceFingerprint: LocalUsageSourceFingerprint?
    var lastFingerprintCheckedAt: Date?
    var lastError: String?
    var isStaleFallback: Bool
}

struct LocalUsageHistoryState: Equatable, Sendable {
    var summary: LocalUsageSummary?
    var error: String?
    var isLoading: Bool
    var lastRefreshedAt: Date?
    var sourceFingerprint: LocalUsageSourceFingerprint?
    var lastFingerprintCheckedAt: Date?
    var isStaleFallback: Bool
}

struct LocalUsageHistoryLoadResult: Sendable {
    var summary: LocalUsageSummary
    var sourceFingerprint: LocalUsageSourceFingerprint
}

enum LocalUsageSourceFingerprintBuilder {
    static func codexFingerprint(scope: LocalUsageTrendScope) -> LocalUsageSourceFingerprint {
        let codexRoot = "\(NSHomeDirectory())/.codex"
        switch scope {
        case .allAccounts:
            return fingerprint(
                roots: [
                    "\(codexRoot)/sessions",
                    "\(codexRoot)/archived_sessions"
                ],
                includeFile: { $0.pathExtension.lowercased() == "jsonl" }
            )
        case .currentAccount:
            return fingerprint(
                roots: ["\(codexRoot)/logs_2.sqlite"],
                includeFile: { _ in true }
            )
        }
    }

    static func claudeFingerprint(
        scope: LocalUsageTrendScope,
        currentConfigDir: String?,
        allConfigDirs: [String]
    ) -> LocalUsageSourceFingerprint {
        let defaultRoot = "\(NSHomeDirectory())/.claude/projects"
        let normalizedAllConfigDirs = allConfigDirs.compactMap(normalizedDirectoryPath)
        let allRoots = uniquePaths(
            [defaultRoot] + normalizedAllConfigDirs.map(projectsRoot(fromConfigDir:))
        )

        let roots: [String]
        switch scope {
        case .allAccounts:
            roots = allRoots
        case .currentAccount:
            if let currentConfigDir = normalizedDirectoryPath(currentConfigDir) {
                roots = [projectsRoot(fromConfigDir: currentConfigDir)]
            } else {
                roots = [defaultRoot]
            }
        }

        return fingerprint(
            roots: roots,
            includeFile: { $0.pathExtension.lowercased() == "jsonl" }
        )
    }

    static func kimiFingerprint() -> LocalUsageSourceFingerprint {
        fingerprint(
            roots: ["\(NSHomeDirectory())/.kimi/sessions"],
            includeFile: { $0.lastPathComponent == "wire.jsonl" }
        )
    }

    static func fingerprint(
        roots: [String],
        fileManager: FileManager = .default,
        includeFile: (URL) -> Bool
    ) -> LocalUsageSourceFingerprint {
        let normalizedRoots = roots
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL.path }
            .sorted()
        var files: [URL] = []

        for root in normalizedRoots {
            let rootURL = URL(fileURLWithPath: root)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory) else {
                continue
            }

            if !isDirectory.boolValue {
                if includeFile(rootURL) {
                    files.append(rootURL)
                }
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator where includeFile(fileURL) {
                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                      values.isRegularFile == true else {
                    continue
                }
                files.append(fileURL)
            }
        }

        var totalSize: UInt64 = 0
        var latestModificationTime: Date?
        for fileURL in files {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                continue
            }
            if let fileSize = values.fileSize, fileSize > 0 {
                totalSize += UInt64(fileSize)
            }
            if let modifiedAt = values.contentModificationDate,
               latestModificationTime == nil || modifiedAt > (latestModificationTime ?? .distantPast) {
                latestModificationTime = modifiedAt
            }
        }

        return LocalUsageSourceFingerprint(
            roots: normalizedRoots,
            fileCount: files.count,
            totalSize: totalSize,
            latestModificationTime: latestModificationTime
        )
    }

    private static func projectsRoot(fromConfigDir configDir: String) -> String {
        URL(fileURLWithPath: configDir, isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .path
    }

    private static func normalizedDirectoryPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    private static func uniquePaths(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for path in paths where seen.insert(path).inserted {
            output.append(path)
        }
        return output
    }
}

@MainActor
final class LocalUsageHistoryRepository {
    typealias FingerprintProvider = @Sendable () -> LocalUsageSourceFingerprint
    typealias Loader = @Sendable (_ sourceFingerprint: LocalUsageSourceFingerprint) throws -> LocalUsageHistoryLoadResult

    private struct CachePayload: Codable {
        var entries: [LocalUsageHistoryEntry]
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let nowProvider: () -> Date
    private var entries: [LocalUsageHistoryQuery: LocalUsageHistoryEntry] = [:]
    private var loadingTasks: [LocalUsageHistoryQuery: Task<Void, Never>] = [:]

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.nowProvider = nowProvider
        let rootDirectory: URL
        if let baseDirectoryURL {
            rootDirectory = baseDirectoryURL
        } else {
            rootDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        }
        self.fileURL = rootDirectory
            .appendingPathComponent("AIPlanMonitor", isDirectory: true)
            .appendingPathComponent("local_usage_history_cache.json")
        restoreFromDisk()
    }

    func snapshot(for query: LocalUsageHistoryQuery) -> LocalUsageHistoryState {
        let entry = entries[query]
        return LocalUsageHistoryState(
            summary: entry?.summary,
            error: entry?.lastError,
            isLoading: loadingTasks[query] != nil,
            lastRefreshedAt: entry?.refreshedAt,
            sourceFingerprint: entry?.sourceFingerprint,
            lastFingerprintCheckedAt: entry?.lastFingerprintCheckedAt,
            isStaleFallback: entry?.isStaleFallback ?? false
        )
    }

    func refreshIfNeeded(
        query: LocalUsageHistoryQuery,
        force: Bool = false,
        ttl: TimeInterval = RuntimeDiagnosticsLimits.localUsageTrendCacheEntryTTL,
        fingerprintProbeInterval: TimeInterval = RuntimeDiagnosticsLimits.localUsageTrendFingerprintProbeInterval,
        fingerprintProvider: @escaping FingerprintProvider,
        loader: @escaping Loader,
        onStateChange: @escaping @MainActor () -> Void
    ) {
        prune(now: nowProvider())
        guard loadingTasks[query] == nil else { return }

        let now = nowProvider()
        if !force,
           let entry = entries[query],
           let summary = entry.summary,
           now.timeIntervalSince(entry.refreshedAt) < ttl,
           isSummaryTemporallyFresh(summary, now: now),
           !shouldProbeFingerprint(entry: entry, now: now, interval: fingerprintProbeInterval) {
            return
        }

        loadingTasks[query] = Task { @MainActor [weak self] in
            guard let self else { return }
            onStateChange()

            let fingerprint = await Task.detached(priority: .utility) {
                fingerprintProvider()
            }.value

            if !force,
               var entry = entries[query],
               let summary = entry.summary,
               entry.sourceFingerprint == fingerprint,
               isSummaryTemporallyFresh(summary, now: nowProvider()) {
                let validatedAt = nowProvider()
                entry.refreshedAt = validatedAt
                entry.lastFingerprintCheckedAt = validatedAt
                entry.lastError = nil
                entry.isStaleFallback = false
                entries[query] = entry
                loadingTasks.removeValue(forKey: query)
                prune(now: entry.refreshedAt)
                persist()
                onStateChange()
                return
            }

            let result = await Task.detached(priority: .utility) {
                Result<LocalUsageHistoryLoadResult, Error> {
                    try loader(fingerprint)
                }
            }.value

            loadingTasks.removeValue(forKey: query)
            let refreshedAt = nowProvider()
            switch result {
            case .success(let loadResult):
                entries[query] = LocalUsageHistoryEntry(
                    query: query,
                    summary: RuntimeBoundedState.slimmedLocalUsageSummaryForCache(loadResult.summary),
                    refreshedAt: refreshedAt,
                    sourceFingerprint: loadResult.sourceFingerprint,
                    lastFingerprintCheckedAt: refreshedAt,
                    lastError: nil,
                    isStaleFallback: false
                )
            case .failure(let error):
                if var existing = entries[query], existing.summary != nil {
                    existing.refreshedAt = refreshedAt
                    existing.lastFingerprintCheckedAt = refreshedAt
                    existing.lastError = error.localizedDescription
                    existing.isStaleFallback = true
                    entries[query] = existing
                } else {
                    entries[query] = LocalUsageHistoryEntry(
                        query: query,
                        summary: nil,
                        refreshedAt: refreshedAt,
                        sourceFingerprint: fingerprint,
                        lastFingerprintCheckedAt: refreshedAt,
                        lastError: error.localizedDescription,
                        isStaleFallback: false
                    )
                }
            }

            prune(now: refreshedAt)
            persist()
            onStateChange()
        }

        onStateChange()
    }

    func restoreFromDisk() {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let payload = try? decoder.decode(CachePayload.self, from: data) else {
            return
        }
        entries = Dictionary(uniqueKeysWithValues: payload.entries.map { ($0.query, $0) })
        prune(now: nowProvider())
    }

    func persist() {
        do {
            try ensureDirectoryExists()
            let payload = CachePayload(
                entries: entries.values.sorted { lhs, rhs in
                    if lhs.refreshedAt != rhs.refreshedAt {
                        return lhs.refreshedAt > rhs.refreshedAt
                    }
                    return lhs.query.providerID < rhs.query.providerID
                }
            )
            let data = try encoder.encode(payload)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }

    private func prune(now: Date) {
        let ttl = max(30, RuntimeDiagnosticsLimits.localUsageTrendCacheEntryTTL)
        let cutoff = now.addingTimeInterval(-ttl)
        entries = entries.filter { _, entry in
            entry.refreshedAt >= cutoff || entry.summary != nil
        }

        let maxEntries = max(1, RuntimeDiagnosticsLimits.localUsageTrendCacheMaxEntries)
        guard entries.count > maxEntries else { return }

        let keepQueries = Set(
            entries.values
                .sorted { lhs, rhs in
                    if lhs.refreshedAt != rhs.refreshedAt {
                        return lhs.refreshedAt > rhs.refreshedAt
                    }
                    return lhs.query.providerID < rhs.query.providerID
                }
                .prefix(maxEntries)
                .map(\.query)
        )
        entries = entries.filter { keepQueries.contains($0.key) }
    }

    private func shouldProbeFingerprint(
        entry: LocalUsageHistoryEntry,
        now: Date,
        interval: TimeInterval
    ) -> Bool {
        guard entry.sourceFingerprint != nil else { return true }
        let reference = entry.lastFingerprintCheckedAt ?? entry.refreshedAt
        return now.timeIntervalSince(reference) >= max(5, interval)
    }

    private func isSummaryTemporallyFresh(_ summary: LocalUsageSummary, now: Date) -> Bool {
        Calendar.current.isDate(summary.generatedAt, equalTo: now, toGranularity: .hour)
    }

    private func ensureDirectoryExists() throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
