import Foundation
import XCTest
@testable import AIPlanMonitor

final class CodexQuotaDisplayNormalizerTests: XCTestCase {
    func testInactiveExpiredSessionWindowRollsForwardAndResetsToFull() throws {
        let base = Date(timeIntervalSince1970: 10_000)
        let snapshot = makeSnapshot(
            sessionReset: base.addingTimeInterval(-60),
            weeklyReset: base.addingTimeInterval(86_400),
            sessionRemaining: 0,
            sessionUsed: 100
        )

        let normalized = CodexQuotaDisplayNormalizer.normalize(snapshot: snapshot, isActive: false, now: base)

        let session = try XCTUnwrap(normalized.quotaWindows.first(where: { $0.kind == .session }))
        XCTAssertEqual(session.remainingPercent, 100)
        XCTAssertEqual(session.usedPercent, 0)
        XCTAssertEqual(session.resetAt, snapshot.quotaWindows[0].resetAt?.addingTimeInterval(5 * 60 * 60))
        XCTAssertEqual(normalized.used, 0)
        XCTAssertEqual(normalized.remaining, 60)
    }

    func testInactiveExpiredWindowKeepsRollingAcrossMultipleCycles() throws {
        let base = Date(timeIntervalSince1970: 20_000)
        let originalReset = base.addingTimeInterval(-(11 * 60 * 60))
        let snapshot = makeSnapshot(
            sessionReset: originalReset,
            weeklyReset: base.addingTimeInterval(86_400),
            sessionRemaining: 0,
            sessionUsed: 100
        )

        let normalized = CodexQuotaDisplayNormalizer.normalize(snapshot: snapshot, isActive: false, now: base)

        let session = try XCTUnwrap(normalized.quotaWindows.first(where: { $0.kind == .session }))
        XCTAssertEqual(session.resetAt, originalReset.addingTimeInterval(15 * 60 * 60))
        XCTAssertEqual(session.remainingPercent, 100)
        XCTAssertEqual(session.usedPercent, 0)
    }

    func testActiveSnapshotIsNotMutated() {
        let base = Date(timeIntervalSince1970: 30_000)
        let snapshot = makeSnapshot(
            sessionReset: base.addingTimeInterval(-120),
            weeklyReset: base.addingTimeInterval(86_400),
            sessionRemaining: 0,
            sessionUsed: 100
        )

        let normalized = CodexQuotaDisplayNormalizer.normalize(snapshot: snapshot, isActive: true, now: base)

        XCTAssertEqual(normalized, snapshot)
    }

    private func makeSnapshot(
        sessionReset: Date?,
        weeklyReset: Date?,
        sessionRemaining: Double,
        sessionUsed: Double
    ) -> UsageSnapshot {
        UsageSnapshot(
            source: "codex-official",
            status: .ok,
            remaining: min(sessionRemaining, 60),
            used: sessionUsed,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "test",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "session",
                    title: "5h",
                    remainingPercent: sessionRemaining,
                    usedPercent: sessionUsed,
                    resetAt: sessionReset,
                    kind: .session
                ),
                UsageQuotaWindow(
                    id: "weekly",
                    title: "Weekly",
                    remainingPercent: 60,
                    usedPercent: 40,
                    resetAt: weeklyReset,
                    kind: .weekly
                )
            ],
            sourceLabel: "API",
            accountLabel: "user@example.com",
            extras: [:],
            rawMeta: [:]
        )
    }
}
