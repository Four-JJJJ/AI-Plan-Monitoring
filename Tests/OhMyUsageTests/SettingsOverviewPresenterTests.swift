import XCTest
@testable import OhMyUsage

final class SettingsOverviewPresenterTests: XCTestCase {
    func testCardsSummarizeProvidersPermissionsAndMenubarMode() {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.enabled = true
        var relay = ProviderDescriptor.defaultOpenAilinyu()
        relay.enabled = false

        let cards = SettingsOverviewPresenter.cards(
            providers: [codex, relay],
            statusBarMultiUsageEnabled: true,
            statusBarMultiProviderIDs: [codex.id, relay.id],
            statusBarProviderID: codex.id,
            statusBarAppearanceMode: .followWallpaper,
            statusBarDisplayStyle: .barNamePercent,
            hasNotificationPermission: true,
            secureStorageReady: false,
            fullDiskAccessRelevant: true,
            fullDiskAccessRequested: false,
            fullDiskAccessGranted: true,
            localizedText: Self.english
        )

        XCTAssertEqual(cards.count, 4)
        XCTAssertEqual(cards[0].value, "2")
        XCTAssertEqual(cards[0].detail, "1 official sources, 1 custom sources")
        XCTAssertEqual(cards[1].value, "1")
        XCTAssertEqual(cards[1].detail, "1 currently disabled")
        XCTAssertEqual(cards[2].value, "2/3")
        XCTAssertEqual(cards[3].value, "Multi")
        XCTAssertEqual(cards[3].detail, "Menubar appearance Adaptive · Style Bar + name")
    }

    func testOfficialUsageTrendProvidersOnlyReturnEnabledVisibleOnes() {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.enabled = true
        var claude = ProviderDescriptor.defaultOfficialClaude()
        claude.enabled = false

        let providers = SettingsOverviewPresenter.officialUsageTrendProviders(
            providers: [codex, claude],
            shouldShow: { $0.type == .codex }
        )

        XCTAssertEqual(providers.map(\.id), [codex.id])
    }

    func testOfficialUsageTrendTitleLocalizesByLanguage() {
        XCTAssertEqual(
            SettingsOverviewPresenter.officialUsageTrendTitle(displayName: "Codex", language: .zhHans),
            "Codex 使用趋势"
        )
        XCTAssertEqual(
            SettingsOverviewPresenter.officialUsageTrendTitle(displayName: "Codex", language: .en),
            "Codex Usage Trend"
        )
    }

    func testLastRefreshTextFallsBackAndFormatsElapsedTime() {
        let now = Date(timeIntervalSince1970: 3_600)

        XCTAssertEqual(
            SettingsOverviewPresenter.lastRefreshText(
                lastUpdatedAt: nil,
                now: now,
                language: .en,
                localizedText: Self.english
            ),
            "Not refreshed yet"
        )

        XCTAssertEqual(
            SettingsOverviewPresenter.lastRefreshText(
                lastUpdatedAt: Date(timeIntervalSince1970: 3_000),
                now: now,
                language: .en,
                localizedText: Self.english
            ),
            "10m ago"
        )
    }

    private static func english(_ zhHans: String, _ english: String) -> String {
        english
    }
}
