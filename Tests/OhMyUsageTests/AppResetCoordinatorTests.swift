import XCTest
@testable import OhMyUsage

@MainActor
final class AppResetCoordinatorTests: XCTestCase {
    func testResetLocalAppDataRunsHooksInOrder() {
        let coordinator = AppResetCoordinator()
        var events: [String] = []

        coordinator.resetLocalAppData(
            using: AppResetCoordinator.ResetHooks(
                stopPollingAndTransientTasks: { events.append("stop") },
                cancelOAuthImports: { events.append("cancel-imports") },
                resetRuntimeComponents: { events.append("reset-runtime") },
                clearInMemoryState: { events.append("clear-memory") },
                resetPersistentState: { events.append("reset-persistent") },
                restoreDefaultState: { events.append("restore-defaults") },
                rebootstrap: { events.append("rebootstrap") }
            )
        )

        XCTAssertEqual(
            events,
            [
                "stop",
                "cancel-imports",
                "reset-runtime",
                "clear-memory",
                "reset-persistent",
                "restore-defaults",
                "rebootstrap"
            ]
        )
    }
}
