import Foundation
import XCTest
@testable import OhMyUsageApplication
@testable import OhMyUsage

final class UsageAnalyticsRepositoryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UsageAnalyticsRepository.clearSourceFingerprintCacheForTesting()
    }

    override func tearDown() {
        UsageAnalyticsRepository.clearSourceFingerprintCacheForTesting()
        super.tearDown()
    }

    func testUsageAnalyticsFilterDefaultsToLast30DaysRange() {
        XCTAssertEqual(UsageAnalyticsFilter().range, .last30Days)
    }

    func testApplicationTargetOwnsUsageAnalyticsAggregation() throws {
        let now = try fixedDate("2026-05-16T12:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let interval = OhMyUsageApplication.UsageAnalyticsAggregator.rangeInterval(
            .last7Days,
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(interval.start, try fixedDate("2026-05-10T00:00:00Z"))
        XCTAssertEqual(interval.end, try fixedDate("2026-05-17T00:00:00Z"))
    }

    func testCacheStoreRestoresSnapshotFromDiskForFilter() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("usage-analytics-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = try fixedDate("2026-05-16T12:00:00Z")
        let filter = UsageAnalyticsFilter(mode: .all, selectedModelID: nil, range: .last7Days)
        let snapshot = UsageAnalyticsSnapshot(
            generatedAt: now,
            filter: filter,
            totals: UsageMetricTotals(requestCount: 2, successCount: 2, inputTokens: 100, outputTokens: 50),
            trendBuckets: [],
            providerCategoryStats: [],
            providerStats: [],
            modelStats: [],
            availableModels: [],
            diagnostics: []
        )
        let fingerprint = UsageAnalyticsSourceFingerprint(
            ccSwitch: UsageAnalyticsFileFingerprint(roots: ["/tmp/cc-switch.db"], fileCount: 1, totalSize: 128, latestModificationTime: now),
            codex: UsageAnalyticsFileFingerprint(roots: ["/tmp/codex"], fileCount: 2, totalSize: 256, latestModificationTime: now),
            claude: UsageAnalyticsFileFingerprint(roots: ["/tmp/claude"], fileCount: 3, totalSize: 512, latestModificationTime: now),
            kimi: UsageAnalyticsFileFingerprint(roots: ["/tmp/kimi"], fileCount: 4, totalSize: 1024, latestModificationTime: now)
        )

        let writer = UsageAnalyticsSnapshotCacheStore(baseDirectoryURL: root, nowProvider: { now })
        writer.save(snapshot: snapshot, sourceFingerprint: fingerprint)

        let reader = UsageAnalyticsSnapshotCacheStore(baseDirectoryURL: root, nowProvider: { now })
        let entry = try XCTUnwrap(reader.entry(for: filter))

        XCTAssertEqual(entry.snapshot, snapshot)
        XCTAssertEqual(entry.sourceFingerprint, fingerprint)
    }

    func testCacheStoreSkipsFingerprintProbeWithinInterval() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("usage-analytics-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let refreshedAt = try fixedDate("2026-05-16T12:00:00Z")
        var now = refreshedAt
        let filter = UsageAnalyticsFilter(mode: .all, selectedModelID: nil, range: .last24Hours)
        let snapshot = UsageAnalyticsSnapshot.empty(filter: filter, generatedAt: refreshedAt)
        let store = UsageAnalyticsSnapshotCacheStore(baseDirectoryURL: root, nowProvider: { now })

        store.save(snapshot: snapshot, sourceFingerprint: nil)

        now = refreshedAt.addingTimeInterval(30)
        XCTAssertFalse(
            store.shouldProbeFingerprint(
                for: filter,
                now: now,
                interval: 60
            )
        )

        now = refreshedAt.addingTimeInterval(61)
        XCTAssertTrue(
            store.shouldProbeFingerprint(
                for: filter,
                now: now,
                interval: 60
            )
        )
    }

    func testCacheStoreTreatsHourlyRangeAsStaleAcrossHourBoundary() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("usage-analytics-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let refreshedAt = try fixedDate("2026-05-16T12:59:00Z")
        let filter = UsageAnalyticsFilter(mode: .all, selectedModelID: nil, range: .last24Hours)
        let snapshot = UsageAnalyticsSnapshot.empty(filter: filter, generatedAt: refreshedAt)
        let store = UsageAnalyticsSnapshotCacheStore(baseDirectoryURL: root, nowProvider: { refreshedAt })

        store.save(snapshot: snapshot, sourceFingerprint: nil)

        XCTAssertFalse(
            store.isEntryTemporallyFresh(
                for: filter,
                now: try fixedDate("2026-05-16T13:00:01Z"),
                calendar: calendar,
                ttl: 15 * 60
            )
        )
    }

    func testRepositorySourceFingerprintReusesLocalProviderWithinTTLForNormalizedClaudeDirs() throws {
        var now = try fixedDate("2026-05-16T12:00:00Z")
        var ccSwitchCallCount = 0
        var localProviderCallCount = 0
        let repository = UsageAnalyticsRepository(
            ccSwitchReader: CCSwitchUsageLogReader(databasePath: "/tmp/missing-cc-switch-\(UUID().uuidString).db"),
            nowProvider: { now },
            ccSwitchSourceFingerprintProvider: { _ in
                ccSwitchCallCount += 1
                return Self.fileFingerprint(root: "/tmp/cc-switch-\(ccSwitchCallCount).db", seed: ccSwitchCallCount)
            },
            localSourceFingerprintProvider: { claudeDirs in
                localProviderCallCount += 1
                let modificationTime = Date(timeIntervalSince1970: TimeInterval(localProviderCallCount))
                return UsageAnalyticsRepository.CachedLocalSourceFingerprint(
                    codex: UsageAnalyticsFileFingerprint(
                        roots: ["/tmp/codex-\(localProviderCallCount)"],
                        fileCount: localProviderCallCount,
                        totalSize: UInt64(localProviderCallCount),
                        latestModificationTime: modificationTime
                    ),
                    claude: UsageAnalyticsFileFingerprint(
                        roots: claudeDirs,
                        fileCount: localProviderCallCount,
                        totalSize: UInt64(localProviderCallCount),
                        latestModificationTime: modificationTime
                    ),
                    kimi: UsageAnalyticsFileFingerprint(
                        roots: ["/tmp/kimi-\(localProviderCallCount)"],
                        fileCount: localProviderCallCount,
                        totalSize: UInt64(localProviderCallCount),
                        latestModificationTime: modificationTime
                    )
                )
            }
        )

        let first = repository.sourceFingerprint(claudeAllConfigDirs: ["/tmp/claude-a", "/tmp/claude-b"])

        now = now.addingTimeInterval(30)
        let second = repository.sourceFingerprint(claudeAllConfigDirs: [" /tmp/claude-b ", "/tmp/claude-a"])
        XCTAssertNotEqual(second.ccSwitch, first.ccSwitch)
        XCTAssertEqual(second.codex, first.codex)
        XCTAssertEqual(second.claude, first.claude)
        XCTAssertEqual(second.kimi, first.kimi)
        XCTAssertEqual(ccSwitchCallCount, 2)
        XCTAssertEqual(localProviderCallCount, 1)

        _ = repository.sourceFingerprint(claudeAllConfigDirs: ["/tmp/claude-c"])
        XCTAssertEqual(localProviderCallCount, 2)

        now = now.addingTimeInterval(31)
        let expired = repository.sourceFingerprint(claudeAllConfigDirs: ["/tmp/claude-b", "/tmp/claude-a"])
        XCTAssertNotEqual(expired.codex, first.codex)
        XCTAssertNotEqual(expired.claude, first.claude)
        XCTAssertNotEqual(expired.kimi, first.kimi)
        XCTAssertEqual(localProviderCallCount, 3)
    }

    func testRepositorySourceFingerprintReadsCCSwitchForEachReaderWithoutLocalCacheKeyCollision() throws {
        let now = try fixedDate("2026-05-16T12:00:00Z")
        var ccSwitchProviderCallCount = 0
        var localProviderCallCount = 0
        let localProvider: UsageAnalyticsRepository.LocalSourceFingerprintProvider = { _ in
            localProviderCallCount += 1
            return Self.localSourceFingerprint(seed: localProviderCallCount)
        }
        let firstDatabasePath = "/tmp/missing-cc-switch-\(UUID().uuidString)-a.db"
        let secondDatabasePath = "/tmp/missing-cc-switch-\(UUID().uuidString)-b.db"
        let firstRepository = UsageAnalyticsRepository(
            ccSwitchReader: CCSwitchUsageLogReader(databasePath: firstDatabasePath),
            nowProvider: { now },
            ccSwitchSourceFingerprintProvider: { reader in
                ccSwitchProviderCallCount += 1
                return Self.fileFingerprint(root: reader.sourceFingerprintCacheIdentity, seed: ccSwitchProviderCallCount)
            },
            localSourceFingerprintProvider: localProvider
        )
        let secondRepository = UsageAnalyticsRepository(
            ccSwitchReader: CCSwitchUsageLogReader(databasePath: secondDatabasePath),
            nowProvider: { now },
            ccSwitchSourceFingerprintProvider: { reader in
                ccSwitchProviderCallCount += 1
                return Self.fileFingerprint(root: reader.sourceFingerprintCacheIdentity, seed: ccSwitchProviderCallCount)
            },
            localSourceFingerprintProvider: localProvider
        )

        let first = firstRepository.sourceFingerprint(claudeAllConfigDirs: [])
        let second = secondRepository.sourceFingerprint(claudeAllConfigDirs: [])

        XCTAssertEqual(first.ccSwitch.roots, [firstDatabasePath])
        XCTAssertEqual(second.ccSwitch.roots, [secondDatabasePath])
        XCTAssertEqual(ccSwitchProviderCallCount, 2)
        XCTAssertEqual(localProviderCallCount, 1)
    }

    func testRepositorySourceFingerprintRefreshesLocalFingerprintAfterCacheTTL() throws {
        var now = try fixedDate("2026-05-16T12:00:00Z")
        var localProviderCallCount = 0
        let repository = UsageAnalyticsRepository(
            ccSwitchReader: CCSwitchUsageLogReader(databasePath: "/tmp/missing-cc-switch-\(UUID().uuidString).db"),
            nowProvider: { now },
            ccSwitchSourceFingerprintProvider: { _ in Self.fileFingerprint(root: "/tmp/cc-switch.db", seed: 1) },
            localSourceFingerprintProvider: { _ in
                localProviderCallCount += 1
                return Self.localSourceFingerprint(seed: localProviderCallCount)
            }
        )
        let first = repository.sourceFingerprint(claudeAllConfigDirs: [])

        let cached = repository.sourceFingerprint(claudeAllConfigDirs: [])
        XCTAssertEqual(cached.codex, first.codex)
        XCTAssertEqual(cached.claude, first.claude)
        XCTAssertEqual(cached.kimi, first.kimi)
        XCTAssertEqual(localProviderCallCount, 1)

        now = now.addingTimeInterval(61)
        let second = repository.sourceFingerprint(claudeAllConfigDirs: [])

        XCTAssertNotEqual(first.codex, second.codex)
        XCTAssertNotEqual(first.claude, second.claude)
        XCTAssertNotEqual(first.kimi, second.kimi)
        XCTAssertEqual(localProviderCallCount, 2)
    }

    func testRepositorySourceFingerprintRefreshesCCSwitchWithinLocalCacheTTL() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("usage-analytics-fingerprint-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let databaseURL = root.appendingPathComponent("cc-switch.db")
        try Data("first".utf8).write(to: databaseURL)

        var now = try fixedDate("2026-05-16T12:00:00Z")
        let repository = UsageAnalyticsRepository(
            ccSwitchReader: CCSwitchUsageLogReader(databasePath: databaseURL.path),
            nowProvider: { now }
        )
        let first = repository.sourceFingerprint(claudeAllConfigDirs: [])

        Thread.sleep(forTimeInterval: 0.01)
        try Data("second-version".utf8).write(to: databaseURL)
        now = now.addingTimeInterval(30)
        let second = repository.sourceFingerprint(claudeAllConfigDirs: [])

        XCTAssertNotEqual(first.ccSwitch, second.ccSwitch)
        XCTAssertEqual(first.codex, second.codex)
        XCTAssertEqual(first.claude, second.claude)
        XCTAssertEqual(first.kimi, second.kimi)
    }

    func testSnapshotDeduplicatesBySourcePriorityAndBuildsProviderAndModelStats() throws {
        let now = try fixedDate("2026-05-16T12:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let duplicatedProxy = UsageAnalyticsRecord(
            source: .ccswitchProxy,
            eventAt: now.addingTimeInterval(-600),
            appType: "codex",
            providerID: "relay-a",
            providerName: "FourJ Relay",
            modelID: "gpt-5.5",
            requestID: "req-proxy",
            totals: UsageMetricTotals(
                requestCount: 1,
                successCount: 1,
                inputTokens: 80,
                outputTokens: 50,
                cacheReadTokens: 20,
                cacheWriteTokens: 10
            )
        )
        let duplicatedLocal = UsageAnalyticsRecord(
            source: .ohMyUsageLocal,
            eventAt: now.addingTimeInterval(-590),
            appType: "codex",
            providerID: "codex-local",
            providerName: "Codex",
            modelID: "gpt-5.5",
            requestID: "local-codex",
            totals: UsageMetricTotals(
                requestCount: 1,
                successCount: 1,
                inputTokens: 80,
                outputTokens: 50,
                cacheReadTokens: 20,
                cacheWriteTokens: 10
            )
        )
        let claudeLocal = UsageAnalyticsRecord(
            source: .ohMyUsageLocal,
            eventAt: now.addingTimeInterval(-3_600),
            appType: "claude",
            providerID: "claude-local",
            providerName: "Claude",
            modelID: "claude-sonnet-4-6",
            requestID: "local-claude",
            totals: UsageMetricTotals(
                requestCount: 1,
                successCount: 1,
                inputTokens: 30,
                outputTokens: 20,
                cacheReadTokens: 40,
                cacheWriteTokens: 10
            )
        )
        let codexOfficial = UsageAnalyticsRecord(
            source: .ohMyUsageLocal,
            eventAt: now.addingTimeInterval(-7_200),
            appType: "codex",
            providerID: "codex-local",
            providerName: "Codex",
            modelID: "gpt-5.4",
            requestID: "local-codex-54",
            totals: UsageMetricTotals(
                requestCount: 1,
                successCount: 1,
                inputTokens: 10,
                outputTokens: 5,
                cacheReadTokens: 0,
                cacheWriteTokens: 0
            )
        )

        let snapshot = UsageAnalyticsAggregator.snapshot(
            records: [duplicatedLocal, duplicatedProxy, claudeLocal, codexOfficial],
            filter: UsageAnalyticsFilter(mode: .all, selectedModelID: nil, range: .last24Hours),
            calendar: calendar,
            now: now,
            diagnostics: []
        )

        XCTAssertEqual(snapshot.totals.requestCount, 3)
        XCTAssertEqual(snapshot.totals.totalTokens, 275)
        XCTAssertEqual(snapshot.trendBuckets.count, 24)

        let providerCategories = Dictionary(uniqueKeysWithValues: snapshot.providerCategoryStats.map { ($0.name, $0.totals.totalTokens) })
        XCTAssertEqual(providerCategories["中转代理"], 160)
        XCTAssertEqual(providerCategories["Claude"], 100)
        XCTAssertEqual(providerCategories["GPT 官方"], 15)

        let providerRows = Dictionary(uniqueKeysWithValues: snapshot.providerStats.map { ($0.providerName, $0.totals.totalTokens) })
        XCTAssertEqual(providerRows["FourJ Relay"], 160)
        XCTAssertEqual(providerRows["Claude"], 100)
        XCTAssertEqual(providerRows["Codex"], 15)

        let modelRows = Dictionary(uniqueKeysWithValues: snapshot.modelStats.map { ($0.modelID, $0.totals.totalTokens) })
        XCTAssertEqual(modelRows["gpt-5.5"], 160)
        XCTAssertEqual(modelRows["claude-sonnet-4-6"], 100)
        XCTAssertEqual(modelRows["gpt-5.4"], 15)
    }

    func testSnapshotMergesModelStatsByModelIDAcrossProviders() throws {
        let now = try fixedDate("2026-05-16T12:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let records = [
            UsageAnalyticsRecord(
                source: .ccswitchProxy,
                eventAt: now.addingTimeInterval(-300),
                appType: "codex",
                providerID: "relay-a",
                providerName: "FourJ Relay",
                modelID: "gpt-5.5",
                requestID: "req-relay",
                totals: UsageMetricTotals(requestCount: 2, successCount: 2, inputTokens: 100, outputTokens: 20)
            ),
            UsageAnalyticsRecord(
                source: .ccswitchSession,
                eventAt: now.addingTimeInterval(-200),
                appType: "codex",
                providerID: "_codex_session",
                providerName: "Codex (Session)",
                modelID: "gpt-5.5",
                requestID: "req-session",
                totals: UsageMetricTotals(requestCount: 3, successCount: 3, inputTokens: 200, outputTokens: 30)
            )
        ]

        let snapshot = UsageAnalyticsAggregator.snapshot(
            records: records,
            filter: UsageAnalyticsFilter(mode: .all, selectedModelID: nil, range: .last24Hours),
            calendar: calendar,
            now: now,
            diagnostics: []
        )

        XCTAssertEqual(snapshot.modelStats.map(\.modelID), ["gpt-5.5"])
        XCTAssertEqual(snapshot.modelStats.first?.totals.requestCount, 5)
        XCTAssertEqual(snapshot.modelStats.first?.totals.totalTokens, 350)
    }

    func testSnapshotAppliesModelFilterAndBuildsDailyBuckets() throws {
        let now = try fixedDate("2026-05-16T12:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let records = [
            UsageAnalyticsRecord(
                source: .ccswitchProxy,
                eventAt: try fixedDate("2026-05-15T08:00:00Z"),
                appType: "codex",
                providerID: "relay-a",
                providerName: "FourJ Relay",
                modelID: "gpt-5.5",
                requestID: "req-1",
                totals: UsageMetricTotals(requestCount: 1, successCount: 1, inputTokens: 10, outputTokens: 5)
            ),
            UsageAnalyticsRecord(
                source: .ccswitchProxy,
                eventAt: try fixedDate("2026-05-14T08:00:00Z"),
                appType: "codex",
                providerID: "relay-a",
                providerName: "FourJ Relay",
                modelID: "gpt-5.4",
                requestID: "req-2",
                totals: UsageMetricTotals(requestCount: 1, successCount: 1, inputTokens: 90, outputTokens: 10)
            )
        ]

        let snapshot = UsageAnalyticsAggregator.snapshot(
            records: records,
            filter: UsageAnalyticsFilter(mode: .byModel, selectedModelID: "gpt-5.5", range: .last7Days),
            calendar: calendar,
            now: now,
            diagnostics: []
        )

        XCTAssertEqual(snapshot.totals.totalTokens, 15)
        XCTAssertEqual(snapshot.modelStats.map(\.modelID), ["gpt-5.5"])
        XCTAssertEqual(snapshot.trendBuckets.count, 7)
        XCTAssertTrue(snapshot.availableModels.contains { $0.id == "gpt-5.4" })
        XCTAssertTrue(snapshot.availableModels.contains { $0.id == "gpt-5.5" })
    }

    func testSnapshotAllRangeIncludesOlderRecordsAndBuildsWholeHistoryBuckets() throws {
        let now = try fixedDate("2026-05-16T12:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let records = [
            UsageAnalyticsRecord(
                source: .ccswitchProxy,
                eventAt: try fixedDate("2026-01-03T08:00:00Z"),
                appType: "codex",
                providerID: "relay-a",
                providerName: "FourJ Relay",
                modelID: "gpt-5.5",
                requestID: "old-req",
                totals: UsageMetricTotals(requestCount: 1, successCount: 1, inputTokens: 90, outputTokens: 10)
            ),
            UsageAnalyticsRecord(
                source: .ohMyUsageLocal,
                eventAt: try fixedDate("2026-05-16T08:00:00Z"),
                appType: "claude",
                providerID: "claude-local",
                providerName: "Claude",
                modelID: "claude-sonnet-4-6",
                requestID: "recent-req",
                totals: UsageMetricTotals(requestCount: 1, successCount: 1, inputTokens: 10, outputTokens: 5)
            )
        ]

        let last30Snapshot = UsageAnalyticsAggregator.snapshot(
            records: records,
            filter: UsageAnalyticsFilter(mode: .all, selectedModelID: nil, range: .last30Days),
            calendar: calendar,
            now: now,
            diagnostics: []
        )
        let allSnapshot = UsageAnalyticsAggregator.snapshot(
            records: records,
            filter: UsageAnalyticsFilter(mode: .all, selectedModelID: nil, range: .all),
            calendar: calendar,
            now: now,
            diagnostics: []
        )

        XCTAssertEqual(last30Snapshot.totals.totalTokens, 15)
        XCTAssertEqual(last30Snapshot.trendBuckets.count, 30)
        XCTAssertEqual(allSnapshot.totals.totalTokens, 115)
        XCTAssertEqual(allSnapshot.trendBuckets.count, 20)
        XCTAssertEqual(allSnapshot.trendBuckets.first?.startAt, try fixedDate("2026-01-03T00:00:00Z"))
        XCTAssertEqual(allSnapshot.trendBuckets.last?.startAt, try fixedDate("2026-05-16T00:00:00Z"))
        XCTAssertEqual(allSnapshot.trendBuckets.map(\.totals.totalTokens).filter { $0 > 0 }, [100, 15])
    }

    func testSnapshotAllRangeUsesSevenDayBucketsForShortHistoryAndSplitsWeeks() throws {
        let now = try fixedDate("2026-01-20T12:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let records = [
            analyticsRecord(eventAt: try fixedDate("2026-01-03T08:00:00Z"), totalTokens: 100),
            analyticsRecord(eventAt: try fixedDate("2026-01-10T08:00:00Z"), totalTokens: 200)
        ]

        let snapshot = UsageAnalyticsAggregator.snapshot(
            records: records,
            filter: UsageAnalyticsFilter(mode: .all, selectedModelID: nil, range: .all),
            calendar: calendar,
            now: now,
            diagnostics: []
        )

        XCTAssertEqual(snapshot.trendBuckets.map(\.startAt), [
            try fixedDate("2026-01-03T00:00:00Z"),
            try fixedDate("2026-01-10T00:00:00Z")
        ])
        XCTAssertEqual(snapshot.trendBuckets.map(\.totals.totalTokens), [100, 200])
    }

    func testSnapshotAllRangeUsesMonthBucketsForMediumHistory() throws {
        let now = try fixedDate("2025-12-31T12:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let records = [
            analyticsRecord(eventAt: try fixedDate("2025-01-10T08:00:00Z"), totalTokens: 100),
            analyticsRecord(eventAt: try fixedDate("2025-12-20T08:00:00Z"), totalTokens: 200)
        ]

        let snapshot = UsageAnalyticsAggregator.snapshot(
            records: records,
            filter: UsageAnalyticsFilter(mode: .all, selectedModelID: nil, range: .all),
            calendar: calendar,
            now: now,
            diagnostics: []
        )

        XCTAssertEqual(snapshot.trendBuckets.count, 12)
        XCTAssertEqual(snapshot.trendBuckets.first?.startAt, try fixedDate("2025-01-01T00:00:00Z"))
        XCTAssertEqual(snapshot.trendBuckets.last?.startAt, try fixedDate("2025-12-01T00:00:00Z"))
        XCTAssertEqual(snapshot.trendBuckets.map(\.totals.totalTokens).filter { $0 > 0 }, [100, 200])
    }

    func testSnapshotAllRangeUsesQuarterBucketsForLongHistory() throws {
        let now = try fixedDate("2026-04-30T12:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let records = [
            analyticsRecord(eventAt: try fixedDate("2023-01-10T08:00:00Z"), totalTokens: 100),
            analyticsRecord(eventAt: try fixedDate("2026-04-04T08:00:00Z"), totalTokens: 200)
        ]

        let snapshot = UsageAnalyticsAggregator.snapshot(
            records: records,
            filter: UsageAnalyticsFilter(mode: .all, selectedModelID: nil, range: .all),
            calendar: calendar,
            now: now,
            diagnostics: []
        )

        XCTAssertEqual(snapshot.trendBuckets.count, 14)
        XCTAssertEqual(snapshot.trendBuckets.first?.startAt, try fixedDate("2023-01-01T00:00:00Z"))
        XCTAssertEqual(snapshot.trendBuckets.last?.startAt, try fixedDate("2026-04-01T00:00:00Z"))
        XCTAssertEqual(snapshot.trendBuckets.map(\.totals.totalTokens).filter { $0 > 0 }, [100, 200])
    }

    func testUsageMetricTotalsComputesCacheAndSuccessRates() {
        let totals = UsageMetricTotals(
            requestCount: 4,
            successCount: 3,
            inputTokens: 80,
            outputTokens: 50,
            cacheReadTokens: 20,
            cacheWriteTokens: 10
        )

        XCTAssertEqual(totals.totalTokens, 160)
        XCTAssertEqual(totals.cacheRate, 20.0 / 110.0, accuracy: 0.0001)
        XCTAssertEqual(totals.successRate, 0.75, accuracy: 0.0001)
    }

    private func fixedDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw NSError(domain: "UsageAnalyticsRepositoryTests", code: 1)
        }
        return date
    }

    private func analyticsRecord(eventAt: Date, totalTokens: Int) -> UsageAnalyticsRecord {
        UsageAnalyticsRecord(
            source: .ccswitchProxy,
            eventAt: eventAt,
            appType: "codex",
            providerID: "relay-a",
            providerName: "FourJ Relay",
            modelID: "gpt-5.5",
            requestID: UUID().uuidString,
            totals: UsageMetricTotals(requestCount: 1, successCount: 1, outputTokens: totalTokens)
        )
    }

    private static func fileFingerprint(root: String, seed: Int) -> UsageAnalyticsFileFingerprint {
        UsageAnalyticsFileFingerprint(
            roots: [root],
            fileCount: seed,
            totalSize: UInt64(seed),
            latestModificationTime: Date(timeIntervalSince1970: TimeInterval(seed))
        )
    }

    private static func localSourceFingerprint(seed: Int) -> UsageAnalyticsRepository.CachedLocalSourceFingerprint {
        UsageAnalyticsRepository.CachedLocalSourceFingerprint(
            codex: fileFingerprint(root: "/tmp/codex-\(seed)", seed: seed),
            claude: fileFingerprint(root: "/tmp/claude-\(seed)", seed: seed),
            kimi: fileFingerprint(root: "/tmp/kimi-\(seed)", seed: seed)
        )
    }
}
