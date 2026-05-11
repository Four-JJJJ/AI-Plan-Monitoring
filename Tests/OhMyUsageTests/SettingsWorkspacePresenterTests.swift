import XCTest
@testable import OhMyUsage

final class SettingsWorkspacePresenterTests: XCTestCase {
    func testHeaderPresentationUsesOverviewCopy() {
        let presentation = SettingsWorkspacePresenter.headerPresentation(
            selectedTab: .overview,
            localizedText: Self.english,
            generalTabTitle: "General"
        )

        XCTAssertEqual(presentation.title, "Settings Overview")
        XCTAssertEqual(
            presentation.subtitle,
            "A scannable workspace for monitoring, permissions, and service configuration."
        )
        XCTAssertEqual(presentation.refreshButtonTitle, "Refresh All")
    }

    func testHeaderPresentationUsesCustomEndpointCopy() {
        let presentation = SettingsWorkspacePresenter.headerPresentation(
            selectedTab: .customProviders,
            localizedText: Self.english,
            generalTabTitle: "General"
        )

        XCTAssertEqual(presentation.title, "Custom Endpoints")
        XCTAssertEqual(
            presentation.subtitle,
            "Configure Relay, New API, and third-party balance endpoints."
        )
    }

    func testSidebarPresentationBuildsExpectedSectionsAndLabels() {
        let presentation = SettingsWorkspacePresenter.sidebarPresentation(
            localizedText: Self.english,
            generalTabTitle: "General"
        )

        XCTAssertEqual(presentation.appTitle, "oh-myusage")
        XCTAssertEqual(presentation.appSubtitle, "Monitoring workspace")
        XCTAssertEqual(presentation.sections.map(\.id), ["main"])
        XCTAssertEqual(
            presentation.sections[0].items.map(\.title),
            ["General", "Menubar", "Official", "Relay"]
        )
        XCTAssertEqual(
            presentation.sections[0].items.map(\.tab),
            [.general, .menuBar, .officialProviders, .customProviders]
        )
    }

    private static func english(_ zhHans: String, _ english: String) -> String {
        english
    }
}
