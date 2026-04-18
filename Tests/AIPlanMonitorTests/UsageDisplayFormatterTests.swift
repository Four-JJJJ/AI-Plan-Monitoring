import XCTest
@testable import AIPlanMonitor

final class UsageDisplayFormatterTests: XCTestCase {
    func testPlanTypeResolutionUsesExtrasThenRawMetaAndFiltersPlaceholderValues() {
        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .codex,
                extrasPlanType: "business plan",
                rawPlanType: "Plan Plus"
            ),
            "Business Plan"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .claude,
                extrasPlanType: " unknown ",
                rawPlanType: "team-pro"
            ),
            "Team-Pro"
        )

        XCTAssertNil(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .gemini,
                extrasPlanType: "-",
                rawPlanType: nil
            )
        )
    }

    func testPlanTypeResolutionIsOnlyEnabledForFourOfficialModels() {
        XCTAssertNil(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .copilot,
                extrasPlanType: "Business",
                rawPlanType: "Pro"
            )
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .kimi,
                extrasPlanType: "intermediate",
                rawPlanType: nil
            ),
            "Allegretto"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .kimi,
                extrasPlanType: "LEVEL_ADVANCED",
                rawPlanType: nil
            ),
            "Allegro"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .kimi,
                extrasPlanType: nil,
                rawPlanType: "student plus"
            ),
            "student plus"
        )
    }

    func testCompactNumberZhHansBoundaries() {
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(9_999, language: .zhHans), "9999")
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(10_000, language: .zhHans), "1万")
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(65_300, language: .zhHans), "6.5万")
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(3_200_000, language: .zhHans), "320万")
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(219_000_000, language: .zhHans), "2.2亿")
    }

    func testCompactNumberEnglishBoundaries() {
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(999, language: .en), "999")
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(1_000, language: .en), "1K")
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(2_981, language: .en), "3K")
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(2_900_000, language: .en), "2.9M")
    }

    func testMetricValueTextUsesExpectedUnits() {
        XCTAssertEqual(
            LocalTrendValueFormatter.metricValueText(value: 65_300, metric: .tokens, language: .zhHans),
            "6.5万 tokens"
        )
        XCTAssertEqual(
            LocalTrendValueFormatter.metricValueText(value: 29_000, metric: .responses, language: .zhHans),
            "2.9万次"
        )
        XCTAssertEqual(
            LocalTrendValueFormatter.metricValueText(value: 2_981, metric: .responses, language: .en),
            "3K req"
        )
    }
}
