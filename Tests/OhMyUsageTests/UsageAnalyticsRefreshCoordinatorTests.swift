import Foundation
import XCTest
@testable import OhMyUsage

@MainActor
final class UsageAnalyticsRefreshCoordinatorTests: XCTestCase {
    func testRefreshRestoresFreshCachedSnapshotWithoutLoading() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("usage-analytics-coordinator-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = try fixedDate("2026-05-16T12:00:00Z")
        let filter = UsageAnalyticsFilter(mode: .all, selectedModelID: nil, range: .last7Days)
        let cachedSnapshot = UsageAnalyticsSnapshot.empty(filter: filter, generatedAt: now)
        let fingerprint = UsageAnalyticsSourceFingerprint(
            ccSwitch: UsageAnalyticsFileFingerprint(roots: ["/tmp/cc-switch.db"], fileCount: 1, totalSize: 128, latestModificationTime: now),
            codex: UsageAnalyticsFileFingerprint(roots: ["/tmp/codex"], fileCount: 2, totalSize: 256, latestModificationTime: now),
            claude: UsageAnalyticsFileFingerprint(roots: ["/tmp/claude"], fileCount: 3, totalSize: 512, latestModificationTime: now),
            kimi: UsageAnalyticsFileFingerprint(roots: ["/tmp/kimi"], fileCount: 4, totalSize: 1024, latestModificationTime: now)
        )
        let cacheStore = UsageAnalyticsSnapshotCacheStore(baseDirectoryURL: root, nowProvider: { now })
        cacheStore.save(snapshot: cachedSnapshot, sourceFingerprint: fingerprint)
        let coordinator = UsageAnalyticsRefreshCoordinator(
            repository: UsageAnalyticsRepository(nowProvider: { now }),
            cacheStore: cacheStore
        )

        var snapshots: [UsageAnalyticsSnapshot] = []
        var loadingStates: [Bool] = []

        coordinator.refreshUsageAnalyticsIfNeeded(
            filter: filter,
            currentSnapshotFilter: UsageAnalyticsFilter(),
            claudeAllConfigDirs: [],
            force: false,
            onSnapshotChange: { snapshots.append($0) },
            onLoadingChange: { loadingStates.append($0) }
        )

        XCTAssertEqual(snapshots, [cachedSnapshot])
        XCTAssertEqual(loadingStates, [false])
    }

    private func fixedDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw NSError(domain: "UsageAnalyticsRefreshCoordinatorTests", code: 1)
        }
        return date
    }
}
