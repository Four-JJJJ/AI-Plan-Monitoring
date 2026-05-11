import XCTest
@testable import OhMyUsage

@MainActor
final class SettingsClockControllerTests: XCTestCase {
    func testRestartClockIfNeededTicksImmediatelyWhenVisible() {
        let controller = SettingsClockController()
        var task: Task<Void, Never>?
        var tickedDates: [Date] = []

        controller.restartClockIfNeeded(
            isVisible: true,
            existingTask: &task,
            intervalSeconds: 60
        ) { tickedDates.append($0) }

        XCTAssertNotNil(task)
        XCTAssertEqual(tickedDates.count, 1)

        controller.stopClock(existingTask: &task)
        XCTAssertNil(task)
    }

    func testRestartClockIfNeededDoesNothingWhenHidden() {
        let controller = SettingsClockController()
        var task: Task<Void, Never>?
        var tickCount = 0

        controller.restartClockIfNeeded(
            isVisible: false,
            existingTask: &task,
            intervalSeconds: 60
        ) { _ in tickCount += 1 }

        XCTAssertNil(task)
        XCTAssertEqual(tickCount, 0)
    }

    func testTickUsesProvidedReferenceDate() {
        let controller = SettingsClockController()
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        var updatedDate: Date?

        controller.tick(referenceDate: referenceDate) { updatedDate = $0 }

        XCTAssertEqual(updatedDate, referenceDate)
    }
}
