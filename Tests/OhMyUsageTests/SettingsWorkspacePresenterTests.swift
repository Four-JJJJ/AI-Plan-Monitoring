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
            ["Usage", "General", "Menubar", "Official", "Relay", "Buy me a coffee"]
        )
        XCTAssertEqual(
            presentation.sections[0].items.map(\.tab),
            [.usageAnalytics, .general, .menuBar, .officialProviders, .customProviders, .donate]
        )
        XCTAssertEqual(
            presentation.sections[0].items.map(\.icon),
            [
                "settings_sidebar_usage_icon",
                "settings_sidebar_general_icon",
                "settings_sidebar_menubar_icon",
                "settings_sidebar_official_icon",
                "settings_sidebar_relay_icon",
                "settings_sidebar_donate_icon"
            ]
        )
        XCTAssertEqual(
            presentation.sections[0].items.first?.iconName(isSelected: true),
            "settings_sidebar_usage_icon_selected"
        )
        XCTAssertEqual(
            presentation.sections[0].items.last?.iconName(isSelected: true),
            "settings_sidebar_donate_icon_selected"
        )
    }

    private static func english(_ zhHans: String, _ english: String) -> String {
        english
    }
}
