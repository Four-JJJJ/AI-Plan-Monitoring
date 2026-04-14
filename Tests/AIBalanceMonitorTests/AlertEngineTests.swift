import XCTest
@testable import AIBalanceMonitor

final class AlertEngineTests: XCTestCase {
    func testLowRemainingAlert() {
        let snapshot = UsageSnapshot(
            source: "open",
            status: .warning,
            remaining: 5,
            used: 95,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "",
            rawMeta: [:]
        )
        let rule = AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true)

        XCTAssertTrue(AlertEngine.shouldAlertLowRemaining(snapshot: snapshot, rule: rule))
    }

    func testFailureThresholdAlert() {
        let rule = AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true)

        XCTAssertFalse(AlertEngine.shouldAlertFailures(consecutiveFailures: 1, rule: rule))
        XCTAssertTrue(AlertEngine.shouldAlertFailures(consecutiveFailures: 2, rule: rule))
    }

    func testLowQuotaWindowsAlert() {
        let snapshot = UsageSnapshot(
            source: "codex-official",
            status: .warning,
            remaining: 8,
            used: 92,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "session",
                    title: "5h",
                    remainingPercent: 8,
                    usedPercent: 92,
                    resetAt: nil,
                    kind: .session
                ),
                UsageQuotaWindow(
                    id: "weekly",
                    title: "Weekly",
                    remainingPercent: 30,
                    usedPercent: 70,
                    resetAt: nil,
                    kind: .weekly
                )
            ],
            rawMeta: [:]
        )
        let rule = AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true)

        let windows = AlertEngine.lowQuotaWindows(snapshot: snapshot, rule: rule)
        XCTAssertEqual(windows.map(\.id), ["session"])
    }

    func testClaudeUsedQuotaAlertUsesUsedPercentThreshold() {
        let snapshot = UsageSnapshot(
            source: "claude-official",
            status: .warning,
            remaining: 15,
            used: 85,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "session",
                    title: "5h",
                    remainingPercent: 15,
                    usedPercent: 85,
                    resetAt: nil,
                    kind: .session
                )
            ],
            rawMeta: [:]
        )
        let rule = AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true)

        XCTAssertTrue(AlertEngine.shouldAlertLowRemaining(snapshot: snapshot, rule: rule, displaysUsedQuota: true))
        XCTAssertEqual(
            AlertEngine.lowQuotaWindows(snapshot: snapshot, rule: rule, displaysUsedQuota: true).map(\.id),
            ["session"]
        )
    }
}
