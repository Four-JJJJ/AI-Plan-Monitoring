import XCTest
@testable import AIPlanMonitor

final class ThirdPartyBalanceBaselineTrackerTests: XCTestCase {
    func testDecreaseUsesBaselineAndIncreaseResetsToNewHundredPercent() {
        var tracker = ThirdPartyBalanceBaselineTracker()

        assertPercent(
            tracker.record(remaining: 1000, for: "relay-a", at: Date(timeIntervalSince1970: 1)),
            equals: 100
        )
        assertPercent(
            tracker.record(remaining: 600, for: "relay-a", at: Date(timeIntervalSince1970: 2)),
            equals: 60
        )
        assertPercent(tracker.percent(for: "relay-a"), equals: 60)

        assertPercent(
            tracker.record(remaining: 800, for: "relay-a", at: Date(timeIntervalSince1970: 3)),
            equals: 100
        )
        assertPercent(
            tracker.record(remaining: 400, for: "relay-a", at: Date(timeIntervalSince1970: 4)),
            equals: 50
        )
        assertPercent(tracker.percent(for: "relay-a"), equals: 50)
    }

    func testInvalidRemainingDoesNotUpdateTrackerState() {
        var tracker = ThirdPartyBalanceBaselineTracker()
        _ = tracker.record(remaining: 500, for: "relay-a", at: Date(timeIntervalSince1970: 1))
        _ = tracker.record(remaining: 250, for: "relay-a", at: Date(timeIntervalSince1970: 2))
        assertPercent(tracker.percent(for: "relay-a"), equals: 50)

        XCTAssertNil(tracker.record(remaining: nil, for: "relay-a", at: Date(timeIntervalSince1970: 3)))
        XCTAssertNil(tracker.record(remaining: .nan, for: "relay-a", at: Date(timeIntervalSince1970: 4)))
        XCTAssertNil(tracker.record(remaining: -.infinity, for: "relay-a", at: Date(timeIntervalSince1970: 5)))

        assertPercent(tracker.percent(for: "relay-a"), equals: 50)
        XCTAssertEqual(tracker.entryCount, 1)
    }

    func testMultipleProvidersDoNotInterfere() {
        var tracker = ThirdPartyBalanceBaselineTracker()

        _ = tracker.record(remaining: 1000, for: "relay-a", at: Date(timeIntervalSince1970: 1))
        _ = tracker.record(remaining: 300, for: "relay-b", at: Date(timeIntervalSince1970: 2))
        _ = tracker.record(remaining: 700, for: "relay-a", at: Date(timeIntervalSince1970: 3))
        _ = tracker.record(remaining: 150, for: "relay-b", at: Date(timeIntervalSince1970: 4))

        assertPercent(tracker.percent(for: "relay-a"), equals: 70)
        assertPercent(tracker.percent(for: "relay-b"), equals: 50)
        XCTAssertEqual(tracker.entryCount, 2)
    }

    func testPruneKeepsNewestEntriesAndDropsUnknownProviders() {
        var tracker = ThirdPartyBalanceBaselineTracker()
        _ = tracker.record(remaining: 100, for: "relay-1", at: Date(timeIntervalSince1970: 1))
        _ = tracker.record(remaining: 100, for: "relay-2", at: Date(timeIntervalSince1970: 2))
        _ = tracker.record(remaining: 100, for: "relay-3", at: Date(timeIntervalSince1970: 3))
        _ = tracker.record(remaining: 100, for: "relay-4", at: Date(timeIntervalSince1970: 4))

        tracker.prune(keepingProviderIDs: Set(["relay-2", "relay-3", "relay-4"]), maxEntries: 2)

        XCTAssertEqual(tracker.entryCount, 2)
        XCTAssertFalse(tracker.contains(providerID: "relay-1"))
        XCTAssertFalse(tracker.contains(providerID: "relay-2"))
        XCTAssertTrue(tracker.contains(providerID: "relay-3"))
        XCTAssertTrue(tracker.contains(providerID: "relay-4"))
    }

    private func assertPercent(
        _ value: Double?,
        equals expected: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let value else {
            XCTFail("Expected percent value, got nil", file: file, line: line)
            return
        }
        XCTAssertEqual(value, expected, accuracy: 0.0001, file: file, line: line)
    }
}
