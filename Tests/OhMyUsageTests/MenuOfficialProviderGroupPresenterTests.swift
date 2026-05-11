import XCTest
@testable import OhMyUsage

final class MenuOfficialProviderGroupPresenterTests: XCTestCase {
    func testCompactMetricSegmentsKeepFirstTwoPairs() {
        let displays = [
            metricDisplay(id: "session", title: "5h", valueText: "57%"),
            metricDisplay(id: "weekly", title: "周", valueText: "58%"),
            metricDisplay(id: "monthly", title: "月度", valueText: "12%")
        ]

        let segments = MenuOfficialProviderGroupPresenter.compactMetricSegments(from: displays)

        XCTAssertEqual(
            segments,
            [
                MenuCompactMetricSegmentPresentation(title: "5h", valueText: "57%"),
                MenuCompactMetricSegmentPresentation(title: "周", valueText: "58%")
            ]
        )
    }

    func testCompactMetricSegmentsFallsBackToSingleMetric() {
        let displays = [
            metricDisplay(id: "session", title: "5h", valueText: "100%")
        ]

        let segments = MenuOfficialProviderGroupPresenter.compactMetricSegments(from: displays)

        XCTAssertEqual(
            segments,
            [MenuCompactMetricSegmentPresentation(title: "5h", valueText: "100%")]
        )
    }

    func testCompactMetricSegmentsPreserveLocalizedTitles() {
        let displays = [
            metricDisplay(id: "all", title: "All models", valueText: "60%"),
            metricDisplay(id: "sonnet", title: "Sonnet only", valueText: "N/A")
        ]

        let segments = MenuOfficialProviderGroupPresenter.compactMetricSegments(from: displays)

        XCTAssertEqual(segments[0].title, "All models")
        XCTAssertEqual(segments[1].title, "Sonnet only")
    }

    func testGroupUsesFirstCardAsPrimaryAndOnlySecondaryKeepsSwitchAction() {
        let primary = MenuOfficialProviderGroupPresenter.slotCardPresentation(
            id: "a",
            title: "Codex",
            planType: "Plus",
            subtitle: "active@example.com",
            status: .init(text: "充足", tone: .normal),
            metricDisplays: [
                metricDisplay(id: "session", title: "5h", valueText: "57%"),
                metricDisplay(id: "weekly", title: "周", valueText: "58%")
            ],
            isActive: true,
            canSwitch: true,
            isSwitching: false,
            switchActionLabel: "切换"
        )
        let secondary = MenuOfficialProviderGroupPresenter.slotCardPresentation(
            id: "b",
            title: "Codex",
            planType: "Plus",
            subtitle: "standby@example.com",
            status: .init(text: "充足", tone: .normal),
            metricDisplays: [
                metricDisplay(id: "session", title: "5h", valueText: "100%"),
                metricDisplay(id: "weekly", title: "周", valueText: "89%")
            ],
            isActive: false,
            canSwitch: true,
            isSwitching: false,
            switchActionLabel: "切换"
        )

        let group = MenuOfficialProviderGroupPresenter.group(from: [primary, secondary])

        XCTAssertEqual(group?.primary.id, "a")
        XCTAssertNil(group?.primary.actionLabel)
        XCTAssertEqual(group?.secondary.count, 1)
        XCTAssertEqual(group?.secondary.first?.actionLabel, "切换")
        XCTAssertEqual(group?.secondary.first?.compactMetricSegments.count, 2)
    }

    func testCompactRowsUseStatusOnlyWithoutAdditionalFeedbackText() {
        let failing = MenuOfficialProviderGroupPresenter.slotCardPresentation(
            id: "b",
            title: "Claude",
            planType: "Max 20x",
            subtitle: nil,
            status: .init(text: "故障", tone: .error),
            metricDisplays: [
                metricDisplay(id: "session", title: "5h", valueText: "100%"),
                metricDisplay(id: "weekly", title: "周", valueText: "60%")
            ],
            isActive: false,
            canSwitch: true,
            isSwitching: false,
            switchActionLabel: "切换"
        )

        XCTAssertEqual(failing.status.text, "故障")
        XCTAssertNil(failing.detailText)
        XCTAssertEqual(
            failing.compactMetricSegments,
            [
                MenuCompactMetricSegmentPresentation(title: "5h", valueText: "100%"),
                MenuCompactMetricSegmentPresentation(title: "周", valueText: "60%")
            ]
        )
    }

    private func metricDisplay(
        id: String,
        title: String,
        valueText: String
    ) -> MenuQuotaMetricDisplayPresentation {
        MenuQuotaMetricDisplayPresentation(
            id: id,
            title: title,
            valueText: valueText,
            resetText: "-",
            percent: nil,
            barTone: .normal,
            isBlockedByDepletedQuota: false
        )
    }
}
