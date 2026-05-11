import XCTest
@testable import OhMyUsage

@MainActor
final class AppTransientFeedbackCoordinatorTests: XCTestCase {
    func testSettingNilClearsStoredFeedbackImmediately() {
        let coordinator = AppTransientFeedbackCoordinator<String, String>()
        var values: [String: String] = ["a": "old"]

        coordinator.set(
            nil,
            for: "a",
            currentValue: { values[$0] },
            setValue: { key, value in
                if let value {
                    values[key] = value
                } else {
                    values.removeValue(forKey: key)
                }
            }
        )

        XCTAssertNil(values["a"])
    }

    func testCancelAllPreventsAutoClearSideEffect() async {
        let coordinator = AppTransientFeedbackCoordinator<String, String>(
            clearDelayNanoseconds: 50_000_000
        )
        var values: [String: String] = [:]

        coordinator.set(
            "new",
            for: "a",
            currentValue: { values[$0] },
            setValue: { key, value in
                if let value {
                    values[key] = value
                } else {
                    values.removeValue(forKey: key)
                }
            }
        )
        coordinator.cancelAll()

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(values["a"], "new")
    }
}
