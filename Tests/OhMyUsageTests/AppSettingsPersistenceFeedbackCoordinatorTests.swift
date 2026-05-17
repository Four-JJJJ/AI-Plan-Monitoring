import Foundation
import XCTest
@testable import OhMyUsage

@MainActor
final class AppSettingsPersistenceFeedbackCoordinatorTests: XCTestCase {
    func testApplyFeedbackUpdatesDisplayStateAndReturnsSuccess() {
        let coordinator = AppSettingsPersistenceFeedbackCoordinator(clearDelaySeconds: 1)
        var displayState = SettingsPersistenceDisplayState(
            kind: .idle,
            statusText: nil,
            tone: .neutral
        )
        var errorMessage: String?

        let success = coordinator.apply(
            AppConfigurationPersistenceOutcome(
                success: true,
                feedback: AppConfigurationPersistenceFeedback(
                    kind: .saved,
                    statusText: "Saved",
                    tone: .positive,
                    detail: nil
                )
            )
        ) { state, message in
            displayState = state
            errorMessage = message
        }

        XCTAssertTrue(success)
        XCTAssertEqual(displayState.kind, .saved)
        XCTAssertEqual(displayState.statusText, "Saved")
        XCTAssertEqual(displayState.tone, .positive)
        XCTAssertNil(errorMessage)
    }

    func testApplyFeedbackStoresFailureDetailThenAutoClears() async {
        let coordinator = AppSettingsPersistenceFeedbackCoordinator(clearDelaySeconds: 0.02)
        var displayState = SettingsPersistenceDisplayState(
            kind: .idle,
            statusText: nil,
            tone: .neutral
        )
        var errorMessage: String?

        let success = coordinator.apply(
            AppConfigurationPersistenceOutcome(
                success: false,
                feedback: AppConfigurationPersistenceFeedback(
                    kind: .failed,
                    statusText: "Save Failed",
                    tone: .negative,
                    detail: "disk full"
                )
            )
        ) { state, message in
            displayState = state
            errorMessage = message
        }

        XCTAssertFalse(success)
        XCTAssertEqual(displayState.kind, .failed)
        XCTAssertEqual(errorMessage, "disk full")

        await assertEventually("failure feedback should auto clear") {
            displayState.kind == .idle && errorMessage == nil
        }
    }

    private func assertEventually(
        _ message: String,
        timeout: TimeInterval = 1.0,
        pollInterval: TimeInterval = 0.01,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        XCTAssertTrue(condition(), message)
    }
}
