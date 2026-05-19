import OhMyUsageDomain
import XCTest
import OhMyUsageApplication
@testable import OhMyUsage

@MainActor
final class PresentationSmokeTests: XCTestCase {
    func testMenuPresenterStackProducesRepresentativeOutputs() {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.enabled = true
        var relay = ProviderDescriptor.defaultOpenAilinyu()
        relay.enabled = true
        relay.relayConfig?.adapterID = "generic-newapi"

        let codexSnapshot = UsageSnapshot(
            source: codex.id,
            status: .ok,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "session",
                    title: "5h",
                    remainingPercent: 80,
                    usedPercent: 20,
                    kind: .session
                )
            ],
            sourceLabel: "Codex",
            accountLabel: "codex@example.com",
            rawMeta: [
                "codex.teamId": "team-a",
                "codex.accountLabel": "codex@example.com"
            ]
        )
        let relaySnapshot = UsageSnapshot(
            source: relay.id,
            status: .ok,
            remaining: 90,
            used: 10,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Relay",
            rawMeta: [
                "relay.adapterID": "generic-newapi",
                "account.requestCount": "42",
                "account.tokenPlanCurrentPeriodEnd": "2026-05-09T00:00:00Z"
            ]
        )

        let codexSubtitle = MenuSubtitlePresenter.officialAccountSubtitle(
            providerType: .codex,
            snapshot: codexSnapshot,
            showAccountEmail: true,
            codexTeamAliases: [:]
        )
        let relaySubtitle = MenuSubtitlePresenter.relaySecondaryText(
            provider: relay,
            snapshot: relaySnapshot,
            language: .en
        )
        let status = MenuCardStatePresenter.percentageVisualPresentation(
            snapshot: codexSnapshot,
            errorText: nil,
            healthPercents: [80],
            language: .en,
            tightText: "Tight",
            sufficientText: "Sufficient",
            exhaustedText: "Exhausted",
            disconnectedText: "Disconnected"
        )

        XCTAssertEqual(codexSubtitle, "codex@example.com")
        XCTAssertEqual(relaySubtitle, "Requests 42")
        XCTAssertEqual(status.status.text, "Sufficient")
    }

    func testSettingsAndStatusBarPresenterStackSmoke() {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.enabled = true
        let overviewCards = SettingsOverviewPresenter.cards(
            providers: [codex],
            statusBarMultiUsageEnabled: false,
            statusBarMultiProviderIDs: [],
            statusBarProviderID: codex.id,
            statusBarAppearanceMode: .dark,
            statusBarDisplayStyle: .iconPercent,
            hasNotificationPermission: true,
            secureStorageReady: true,
            fullDiskAccessRelevant: false,
            fullDiskAccessRequested: false,
            fullDiskAccessGranted: false,
            localizedText: { _, en in en }
        )
        let sources = StatusBarDisplaySourceBuilder.displaySources(
            for: [codex],
            style: .iconPercent,
            providerSnapshots: [
                codex.id: UsageSnapshot(
                    source: codex.id,
                    status: .ok,
                    remaining: 75,
                    used: 25,
                    limit: 100,
                    unit: "%",
                    updatedAt: Date(),
                    note: "ok",
                    quotaWindows: [
                        UsageQuotaWindow(
                            id: "session",
                            title: "5h",
                            remainingPercent: 75,
                            usedPercent: 25,
                            kind: .session
                        )
                    ],
                    sourceLabel: "Codex"
                )
            ],
            codexActiveSnapshot: nil,
            claudeDisplaySnapshot: nil,
            thirdPartyBarPercentProvider: { _ in nil }
        )
        let items = StatusBarDisplayPresenter.displayItems(for: sources, style: .iconPercent)

        XCTAssertEqual(overviewCards.count, 4)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "Codex")
        XCTAssertEqual(items[0].valueText, "75%")
    }
}
