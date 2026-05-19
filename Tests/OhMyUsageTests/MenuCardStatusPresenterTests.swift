import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class MenuCardStatusPresenterTests: XCTestCase {
    func testPlanTypeRespectsOfficialDisplayToggleAndFallbacks() {
        var official = ProviderDescriptor.defaultOfficialCodex()
        official.officialConfig?.showPlanTypeInMenuBar = true
        let snapshot = UsageSnapshot(
            source: official.id,
            status: .ok,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Official",
            extras: ["planType": "plus"]
        )

        XCTAssertEqual(
            MenuCardStatusPresenter.planType(for: official, snapshot: snapshot),
            "Plus"
        )

        official.officialConfig?.showPlanTypeInMenuBar = false
        XCTAssertNil(MenuCardStatusPresenter.planType(for: official, snapshot: snapshot))
    }

    func testPercentageStatusUsesFailureTextForCachedFetchHealth() {
        let snapshot = UsageSnapshot(
            source: "relay",
            status: .ok,
            fetchHealth: .authExpired,
            valueFreshness: .cachedFallback,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Relay"
        )

        let status = MenuCardStatusPresenter.percentageStatus(
            healthPercents: [80],
            snapshot: snapshot,
            disconnected: false,
            language: .zhHans,
            tightText: "紧张",
            sufficientText: "充足",
            exhaustedText: "耗尽",
            disconnectedText: "失联"
        )

        XCTAssertEqual(status.text, "故障")
        XCTAssertEqual(status.tone, MenuCardStatusPresentation.Tone.error)
    }

    func testPercentageStatusUsesFailureTextForEmptySnapshotFetchProblems() {
        let snapshot = UsageSnapshot(
            source: "codex",
            status: .ok,
            fetchHealth: .endpointMisconfigured,
            valueFreshness: .empty,
            remaining: nil,
            used: nil,
            limit: nil,
            unit: "%",
            updatedAt: Date(),
            note: "auth expired",
            sourceLabel: "Official"
        )

        let status = MenuCardStatusPresenter.percentageStatus(
            healthPercents: [],
            snapshot: snapshot,
            disconnected: false,
            language: .zhHans,
            tightText: "紧张",
            sufficientText: "充足",
            exhaustedText: "耗尽",
            disconnectedText: "失联"
        )

        XCTAssertEqual(status.text, "故障")
        XCTAssertEqual(status.tone, MenuCardStatusPresentation.Tone.error)
    }

    func testAmountStatusUsesFailureTextForEmptySnapshotFetchProblems() {
        let snapshot = UsageSnapshot(
            source: "relay",
            status: .ok,
            fetchHealth: .rateLimited,
            valueFreshness: .empty,
            remaining: nil,
            used: nil,
            limit: nil,
            unit: "%",
            updatedAt: Date(),
            note: "rate limited",
            sourceLabel: "Relay"
        )

        let status = MenuCardStatusPresenter.amountStatus(
            remaining: nil,
            snapshot: snapshot,
            disconnected: false,
            language: .zhHans,
            tightText: "紧张",
            sufficientText: "充足",
            exhaustedText: "耗尽",
            disconnectedText: "失联"
        )

        XCTAssertEqual(status.text, "故障")
        XCTAssertEqual(status.tone, MenuCardStatusPresentation.Tone.error)
    }

    func testAmountStatusUsesRemainingThresholds() {
        let status = MenuCardStatusPresenter.amountStatus(
            remaining: 12,
            snapshot: nil,
            disconnected: false,
            language: .en,
            tightText: "Tight",
            sufficientText: "Sufficient",
            exhaustedText: "Exhausted",
            disconnectedText: "Disconnected"
        )

        XCTAssertEqual(status.text, "Tight")
        XCTAssertEqual(status.tone, MenuCardStatusPresentation.Tone.warning)
    }

    func testCachedFetchHealthStatusTextSupportsEnglish() {
        XCTAssertEqual(
            MenuCardStatusPresenter.cachedFetchHealthStatusText(.authExpired, language: .en),
            "Failure"
        )
    }
}
