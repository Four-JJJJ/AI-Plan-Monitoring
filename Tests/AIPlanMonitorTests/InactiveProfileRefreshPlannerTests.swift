import Foundation
import XCTest
@testable import AIPlanMonitor

final class InactiveProfileRefreshPlannerTests: XCTestCase {
    func testSelectNextSlotRotatesAndSkipsActiveSlot() {
        let ordered: [CodexSlotID] = [.a, .b, CodexSlotID(rawValue: "C")]
        let active: Set<CodexSlotID> = [.a]

        let first = InactiveProfileRefreshPlanner.selectNextSlot(
            orderedSlotIDs: ordered,
            activeSlotIDs: active,
            inFlightSlotIDs: [],
            retryNotBefore: [:],
            cursor: 0,
            now: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(first?.slotID, .b)
        XCTAssertEqual(first?.nextCursor, 2)

        let second = InactiveProfileRefreshPlanner.selectNextSlot(
            orderedSlotIDs: ordered,
            activeSlotIDs: active,
            inFlightSlotIDs: [],
            retryNotBefore: [:],
            cursor: first?.nextCursor ?? 0,
            now: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(second?.slotID, CodexSlotID(rawValue: "C"))
        XCTAssertEqual(second?.nextCursor, 0)
    }

    func testSelectNextSlotSkipsInFlightSlots() {
        let ordered: [CodexSlotID] = [.a, .b, CodexSlotID(rawValue: "C")]
        let selection = InactiveProfileRefreshPlanner.selectNextSlot(
            orderedSlotIDs: ordered,
            activeSlotIDs: [],
            inFlightSlotIDs: [.a, .b],
            retryNotBefore: [:],
            cursor: 0,
            now: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(selection?.slotID, CodexSlotID(rawValue: "C"))
    }

    func testShouldAttemptProviderRefreshRespectsMinimumInterval() {
        let now = Date(timeIntervalSince1970: 2_000)
        XCTAssertTrue(
            InactiveProfileRefreshPlanner.shouldAttemptProviderRefresh(
                lastAttemptAt: nil,
                minimumInterval: 30,
                now: now
            )
        )
        XCTAssertFalse(
            InactiveProfileRefreshPlanner.shouldAttemptProviderRefresh(
                lastAttemptAt: now.addingTimeInterval(-20),
                minimumInterval: 30,
                now: now
            )
        )
        XCTAssertTrue(
            InactiveProfileRefreshPlanner.shouldAttemptProviderRefresh(
                lastAttemptAt: now.addingTimeInterval(-30),
                minimumInterval: 30,
                now: now
            )
        )
    }

    func testRetryBackoffBlocksSelectionAndSuccessRecovers() throws {
        var retryState = InactiveProfileRefreshRetryState()
        let slot = CodexSlotID.a
        let start = Date(timeIntervalSince1970: 3_000)
        retryState.markFailure(slotID: slot, baseInterval: 60, now: start)
        let notBefore = try XCTUnwrap(retryState.retryNotBefore[slot])
        XCTAssertEqual(notBefore.timeIntervalSince1970, start.addingTimeInterval(120).timeIntervalSince1970, accuracy: 0.001)

        let blocked = InactiveProfileRefreshPlanner.selectNextSlot(
            orderedSlotIDs: [slot],
            activeSlotIDs: [],
            inFlightSlotIDs: [],
            retryNotBefore: retryState.retryNotBefore,
            cursor: 0,
            now: start.addingTimeInterval(60)
        )
        XCTAssertNil(blocked)

        let allowed = InactiveProfileRefreshPlanner.selectNextSlot(
            orderedSlotIDs: [slot],
            activeSlotIDs: [],
            inFlightSlotIDs: [],
            retryNotBefore: retryState.retryNotBefore,
            cursor: 0,
            now: start.addingTimeInterval(121)
        )
        XCTAssertEqual(allowed?.slotID, slot)

        retryState.markSuccess(slotID: slot)
        XCTAssertNil(retryState.retryNotBefore[slot])
        XCTAssertNil(retryState.failureCounts[slot])
        let recovered = InactiveProfileRefreshPlanner.selectNextSlot(
            orderedSlotIDs: [slot],
            activeSlotIDs: [],
            inFlightSlotIDs: [],
            retryNotBefore: retryState.retryNotBefore,
            cursor: 0,
            now: start.addingTimeInterval(10)
        )
        XCTAssertEqual(recovered?.slotID, slot)
    }
}
