import XCTest
@testable import AIPlanMonitor

final class BackoffPolicyTests: XCTestCase {
    func testBackoffUsesBaseIntervalOnSuccess() {
        XCTAssertEqual(BackoffPolicy.delaySeconds(baseInterval: 60, consecutiveFailures: 0), 60)
    }

    func testBackoffUses120OnFirstFailure() {
        XCTAssertEqual(BackoffPolicy.delaySeconds(baseInterval: 60, consecutiveFailures: 1), 120)
    }

    func testBackoffUses300OnRepeatedFailures() {
        XCTAssertEqual(BackoffPolicy.delaySeconds(baseInterval: 60, consecutiveFailures: 2), 300)
        XCTAssertEqual(BackoffPolicy.delaySeconds(baseInterval: 60, consecutiveFailures: 9), 300)
    }
}
