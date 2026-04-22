import XCTest
@testable import AIPlanMonitor

final class StatusBarControllerTraePercentTests: XCTestCase {
    func testTraePrimaryPercentPrefersDollarWindow() {
        let snapshot = UsageSnapshot(
            source: "trae-official",
            status: .ok,
            remaining: 30,
            used: 70,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "test",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "trae-official-autocomplete",
                    title: "自动补全",
                    remainingPercent: 20,
                    usedPercent: 80,
                    resetAt: nil,
                    kind: .custom
                ),
                UsageQuotaWindow(
                    id: "trae-official-dollar",
                    title: "美元余额",
                    remainingPercent: 64,
                    usedPercent: 36,
                    resetAt: nil,
                    kind: .custom
                )
            ],
            sourceLabel: "API"
        )

        assertPercent(StatusBarController.traePrimaryPercent(snapshot: snapshot), equals: 64)
    }

    func testTraePrimaryPercentFallsBackToFirstWindowWhenNoDollarWindow() {
        let snapshot = UsageSnapshot(
            source: "trae-official",
            status: .ok,
            remaining: 30,
            used: 70,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "test",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "window-1",
                    title: "Custom A",
                    remainingPercent: 42,
                    usedPercent: 58,
                    resetAt: nil,
                    kind: .custom
                )
            ],
            sourceLabel: "API"
        )

        assertPercent(StatusBarController.traePrimaryPercent(snapshot: snapshot), equals: 42)
    }

    func testTraePrimaryPercentFallsBackToSnapshotRemainingWhenWindowMissing() {
        let snapshot = UsageSnapshot(
            source: "trae-official",
            status: .ok,
            remaining: 77,
            used: 23,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "test",
            quotaWindows: [],
            sourceLabel: "API"
        )

        assertPercent(StatusBarController.traePrimaryPercent(snapshot: snapshot), equals: 77)
    }

    func testTraePrimaryPercentUsesUsedPercentWhenUsagePreferenceIsUsed() {
        let snapshot = UsageSnapshot(
            source: "trae-official",
            status: .ok,
            remaining: 64,
            used: 36,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "test",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "trae-official-dollar",
                    title: "美元余额",
                    remainingPercent: 64,
                    usedPercent: 36,
                    resetAt: nil,
                    kind: .custom
                )
            ],
            sourceLabel: "API"
        )

        assertPercent(
            StatusBarController.traePrimaryPercent(snapshot: snapshot, displaysUsedQuota: true),
            equals: 36
        )
    }

    func testTraePrimaryPercentFallsBackToRemainingWhenUsedMissing() {
        let snapshot = UsageSnapshot(
            source: "trae-official",
            status: .ok,
            remaining: 61,
            used: nil,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "test",
            quotaWindows: [],
            sourceLabel: "API"
        )

        assertPercent(
            StatusBarController.traePrimaryPercent(snapshot: snapshot, displaysUsedQuota: true),
            equals: 61
        )
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
