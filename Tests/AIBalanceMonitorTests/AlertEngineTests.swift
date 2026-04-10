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
}
