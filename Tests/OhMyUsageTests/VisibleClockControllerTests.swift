import XCTest
import OhMyUsageApplication

@MainActor
final class VisibleClockControllerTests: XCTestCase {
    func testRestartClockIfNeededTicksImmediatelyWhenVisible() {
        let controller = VisibleClockController()
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
        let controller = VisibleClockController()
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

    func testRestartClockIfNeededCancelsExistingTaskWhenHidden() {
        let controller = VisibleClockController()
        let existingTask = Task<Void, Never> {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
            }
        }
        var task: Task<Void, Never>? = existingTask
        var tickCount = 0

        controller.restartClockIfNeeded(
            isVisible: false,
            existingTask: &task,
            intervalSeconds: 60
        ) { _ in tickCount += 1 }

        XCTAssertNil(task)
        XCTAssertTrue(existingTask.isCancelled)
        XCTAssertEqual(tickCount, 0)
    }

    func testRestartClockIfNeededKeepsActiveVisibleTaskWithoutExtraImmediateTick() {
        let controller = VisibleClockController()
        let existingTask = Task<Void, Never> {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
            }
        }
        var task: Task<Void, Never>? = existingTask
        var tickCount = 0

        controller.restartClockIfNeeded(
            isVisible: true,
            existingTask: &task,
            intervalSeconds: 60
        ) { _ in tickCount += 1 }

        XCTAssertNotNil(task)
        XCTAssertFalse(existingTask.isCancelled)
        XCTAssertEqual(tickCount, 0)

        controller.stopClock(existingTask: &task)
    }

    func testStopClockCancelsAndClearsTask() {
        let controller = VisibleClockController()
        let existingTask = Task<Void, Never> {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
            }
        }
        var task: Task<Void, Never>? = existingTask

        controller.stopClock(existingTask: &task)

        XCTAssertNil(task)
        XCTAssertTrue(existingTask.isCancelled)
    }

    func testTickUsesProvidedReferenceDate() {
        let controller = VisibleClockController()
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        var updatedDate: Date?

        controller.tick(referenceDate: referenceDate) { updatedDate = $0 }

        XCTAssertEqual(updatedDate, referenceDate)
    }
}
