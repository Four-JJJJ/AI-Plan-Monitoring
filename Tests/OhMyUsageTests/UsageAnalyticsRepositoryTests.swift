import Foundation
import XCTest
@testable import OhMyUsageApplication
@testable import OhMyUsage

final class UsageAnalyticsRepositoryTests: XCTestCase {
    func testUsageAnalyticsFilterDefaultsToAllRange() {
        XCTAssertEqual(UsageAnalyticsFilter().range, .all)
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

    func testRepositorySourceFingerprintTracksCCSwitchDatabaseChanges() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("usage-analytics-fingerprint-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let databaseURL = root.appendingPathComponent("cc-switch.db")
        try Data("first".utf8).write(to: databaseURL)

        let repository = UsageAnalyticsRepository(
            ccSwitchReader: CCSwitchUsageLogReader(databasePath: databaseURL.path)
        )
        let first = repository.sourceFingerprint(claudeAllConfigDirs: [])

        Thread.sleep(forTimeInterval: 0.01)
        try Data("second-version".utf8).write(to: databaseURL)
        let second = repository.sourceFingerprint(claudeAllConfigDirs: [])

        XCTAssertNotEqual(first.ccSwitch, second.ccSwitch)
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
}
