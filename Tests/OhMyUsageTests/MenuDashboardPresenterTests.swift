import XCTest
@testable import OhMyUsage

final class MenuDashboardPresenterTests: XCTestCase {
    func testUpdatedTextFallsBackWhenNoTimestampExists() {
        let presentation = MenuDashboardPresenter.headerPresentation(
            lastUpdatedAt: nil,
            language: .en,
            now: Date(timeIntervalSince1970: 120),
            updatedAgoLabel: "Updated",
            updateState: .init(
                kind: .idle,
                statusText: nil,
                tone: .neutral,
                retryTitle: nil,
                isRetryEnabled: false
            )
        )

        XCTAssertEqual(presentation.updatedText, "Updated -")
        XCTAssertNil(presentation.update)
    }

    func testUpdateAvailableProducesActionableHeaderState() {
        let presentation = MenuDashboardPresenter.headerPresentation(
            lastUpdatedAt: Date(timeIntervalSince1970: 60),
            language: .en,
            now: Date(timeIntervalSince1970: 120),
            updatedAgoLabel: "Updated",
            updateState: .init(
                kind: .updateAvailable(version: "1.2.3"),
                statusText: "Install 1.2.3",
                tone: .positive,
                retryTitle: nil,
                isRetryEnabled: true
            )
        )

        XCTAssertEqual(presentation.updatedText, "Updated 1m ago")
        XCTAssertEqual(presentation.update?.title, "Install 1.2.3")
        XCTAssertEqual(presentation.update?.tone, .positive)
        XCTAssertEqual(presentation.update?.showsPrimaryAction, true)
        XCTAssertEqual(presentation.update?.accessibilityLabel, "App update status: Install 1.2.3")
    }
}
