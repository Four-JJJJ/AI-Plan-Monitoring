import Foundation
import XCTest
@testable import AIPlanMonitor

final class RuntimeBoundedStateTests: XCTestCase {
    func testAppendSnapshotNoteDedupAndLengthBound() {
        let existing = "network timeout | network timeout | stale cache"
        let deduped = RuntimeBoundedState.appendSnapshotNote(
            existing: existing,
            appending: "network timeout",
            maxLength: 120
        )
        XCTAssertEqual(
            deduped
                .split(separator: "|", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            ["network timeout", "stale cache"]
        )

        let longSegment = String(repeating: "x", count: 320)
        let bounded = RuntimeBoundedState.appendSnapshotNote(
            existing: deduped,
            appending: longSegment,
            maxLength: 140
        )
        XCTAssertLessThanOrEqual(bounded.count, 140)
        XCTAssertTrue(bounded.contains(String(longSegment.suffix(64))))
    }

    func testPruneLocalUsageTrendCachesEvictsExpiredAndLeastRecent() throws {
        let now = try fixedDate("2026-04-20T12:00:00Z")
        var summaries: [String: LocalUsageSummary] = [
            "k1": sampleSummary(seed: 1),
            "k2": sampleSummary(seed: 2),
            "k3": sampleSummary(seed: 3),
            "k4": sampleSummary(seed: 4)
        ]
        var errors: [String: String] = [
            "k1": "e1",
            "k2": "e2",
            "k3": "e3",
            "k4": "e4"
        ]
        var refreshedAt: [String: Date] = [
            "k1": now.addingTimeInterval(-200), // expired
            "k2": now.addingTimeInterval(-50),
            "k3": now.addingTimeInterval(-20),
            "k4": now.addingTimeInterval(-5)
        ]
        var loading: Set<String> = ["k1", "k2", "k3", "k4"]

        let removed = RuntimeBoundedState.pruneLocalUsageTrendCaches(
            summaries: &summaries,
            errors: &errors,
            queryLastRefreshedAt: &refreshedAt,
            loadingQueryKeys: &loading,
            now: now,
            maxEntries: 2,
            ttl: 60
        )

        XCTAssertEqual(removed, Set(["k1", "k2"]))
        XCTAssertEqual(Set(summaries.keys), Set(["k3", "k4"]))
        XCTAssertEqual(Set(errors.keys), Set(["k3", "k4"]))
        XCTAssertEqual(Set(refreshedAt.keys), Set(["k3", "k4"]))
        XCTAssertEqual(loading, Set(["k3", "k4"]))
    }

    func testSlimmedLocalUsageSummaryForCacheDropsModelBreakdown() {
        let summary = sampleSummary(seed: 9)
        XCTAssertFalse(summary.today.byModel.isEmpty)
        XCTAssertFalse(summary.last30Days.byModel.isEmpty)

        let slimmed = RuntimeBoundedState.slimmedLocalUsageSummaryForCache(summary)
        XCTAssertEqual(slimmed.today.totalTokens, summary.today.totalTokens)
        XCTAssertEqual(slimmed.last30Days.responses, summary.last30Days.responses)
        XCTAssertTrue(slimmed.today.byModel.isEmpty)
        XCTAssertTrue(slimmed.yesterday.byModel.isEmpty)
        XCTAssertTrue(slimmed.last30Days.byModel.isEmpty)
        XCTAssertEqual(slimmed.hourly24.count, summary.hourly24.count)
        XCTAssertEqual(slimmed.daily7.count, summary.daily7.count)
    }

    private func sampleSummary(seed: Int) -> LocalUsageSummary {
        let now = Date(timeIntervalSince1970: TimeInterval(1_745_000_000 + seed))
        let modelBreakdown = [
            LocalUsageModelBreakdown(modelID: "gpt-5.4", totalTokens: 120 + seed, responses: 3),
            LocalUsageModelBreakdown(modelID: "gpt-5.4-mini", totalTokens: 80 + seed, responses: 2)
        ]
        let period = LocalUsagePeriodSummary(
            totalTokens: 200 + seed,
            responses: 5,
            byModel: modelBreakdown
        )
        return LocalUsageSummary(
            today: period,
            yesterday: period,
            last30Days: period,
            hourly24: [
                LocalUsageTrendPoint(
                    id: "h-\(seed)",
                    startAt: now,
                    totalTokens: 20 + seed,
                    responses: 1
                )
            ],
            daily7: [
                LocalUsageTrendPoint(
                    id: "d-\(seed)",
                    startAt: now,
                    totalTokens: 50 + seed,
                    responses: 2
                )
            ],
            sourcePath: "/tmp/local-usage-\(seed)",
            generatedAt: now,
            diagnostics: nil,
            isApproximateFallback: false
        )
    }

    private func fixedDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw NSError(domain: "RuntimeBoundedStateTests", code: 1)
        }
        return date
    }
}
