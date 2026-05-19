import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class MenuQuotaPresenterTests: XCTestCase {
    func testVisibleMetricsFallbackUsesClaudePlaceholdersAndUsedSuffix() {
        let provider = ProviderDescriptor.defaultOfficialClaude()

        let metrics = MenuQuotaPresenter.visibleMetrics(
            provider: provider,
            metrics: [],
            language: .en,
            localization: Self.localization
        )

        XCTAssertEqual(metrics.count, 4)
        XCTAssertEqual(metrics[0].title, "5h used")
        XCTAssertEqual(metrics[1].title, "All models used")
        XCTAssertFalse(metrics[2].isAvailable)
        XCTAssertEqual(metrics[2].valueTextOverride, "N/A")
    }

    func testClaudeQuotaMetricsResolveSonnetAndDesignWindows() {
        let provider = ProviderDescriptor.defaultOfficialClaude()
        let snapshot = UsageSnapshot(
            source: provider.id,
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
                    title: "Session",
                    remainingPercent: 75,
                    usedPercent: 25,
                    kind: .session
                ),
                UsageQuotaWindow(
                    id: "weekly",
                    title: "Weekly",
                    remainingPercent: 60,
                    usedPercent: 40,
                    kind: .weekly
                ),
                UsageQuotaWindow(
                    id: "sonnet-window",
                    title: "Sonnet Window",
                    remainingPercent: 50,
                    usedPercent: 50,
                    kind: .custom
                ),
                UsageQuotaWindow(
                    id: "design-window",
                    title: "Claude Design",
                    remainingPercent: 40,
                    usedPercent: 60,
                    kind: .custom
                )
            ],
            sourceLabel: "API"
        )

        let metrics = MenuQuotaPresenter.quotaMetrics(
            provider: provider,
            snapshot: snapshot,
            language: .en,
            localization: Self.localization
        )

        XCTAssertEqual(metrics.count, 4)
        XCTAssertEqual(metrics[0].title, "5h used")
        XCTAssertEqual(metrics[1].title, "All models used")
        XCTAssertEqual(metrics[2].title, "Sonnet only used")
        XCTAssertEqual(metrics[3].title, "Claude Design used")
        XCTAssertEqual(metrics[2].healthPercent ?? -1, 50, accuracy: 0.0001)
        XCTAssertEqual(metrics[3].healthPercent ?? -1, 40, accuracy: 0.0001)
    }

    func testMetricDisplaysUseTraeAmountFallbackWhenUsedValueMissing() {
        var provider = ProviderDescriptor.defaultOfficialTrae()
        provider.officialConfig?.traeValueDisplayMode = .amount

        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 88,
            used: 12,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "API",
            extras: [
                "dollarRemaining": "12.5"
            ]
        )

        let presentations = MenuQuotaPresenter.metricDisplays(
            metrics: [
                MenuQuotaMetric(
                    id: "trae-dollar",
                    title: "Dollar Balance",
                    displayPercent: 88,
                    healthPercent: 88,
                    resetAt: nil,
                    isAvailable: true,
                    valueTextOverride: nil,
                    kind: .credits
                )
            ],
            blockageCandidates: [],
            provider: provider,
            snapshot: snapshot,
            disconnected: false,
            language: .en,
            now: Date()
        )

        XCTAssertEqual(presentations.count, 1)
        XCTAssertEqual(
            presentations[0].valueText,
            TraeValueDisplayFormatter.format(
                12.5,
                kind: .dollarBalance,
                maxWidth: MetricValueLayoutFormatter.metricValueColumnWidth
            )
        )
        XCTAssertEqual(presentations[0].resetText, "-")
        XCTAssertEqual(presentations[0].barTone, .normal)
    }

    func testMetricDisplaysMarkSessionBlockedWhenWeeklyQuotaDepleted() {
        let provider = ProviderDescriptor.defaultOfficialCodex()
        let session = MenuQuotaMetric(
            id: "session",
            title: "5h",
            displayPercent: 42,
            healthPercent: 42,
            resetAt: nil,
            isAvailable: true,
            valueTextOverride: nil,
            kind: .session
        )
        let weekly = MenuQuotaMetric(
            id: "weekly",
            title: "Weekly",
            displayPercent: 0,
            healthPercent: 0,
            resetAt: nil,
            isAvailable: true,
            valueTextOverride: nil,
            kind: .weekly
        )

        let presentations = MenuQuotaPresenter.metricDisplays(
            metrics: [session],
            blockageCandidates: [session, weekly],
            provider: provider,
            snapshot: nil,
            disconnected: false,
            language: .en,
            now: Date()
        )

        XCTAssertTrue(presentations[0].isBlockedByDepletedQuota)
    }

    func testQuotaMetricsRewriteRelayCurrentPlanTitleForXiaomimimoTokenPlan() {
        var provider = ProviderDescriptor.defaultOpenAilinyu()
        provider.relayConfig?.adapterID = "xiaomimimo-token-plan"
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 90,
            used: 10,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "current-plan",
                    title: "Current Plan",
                    remainingPercent: 90,
                    usedPercent: 10,
                    kind: .custom
                )
            ],
            sourceLabel: "Relay"
        )

        let metrics = MenuQuotaPresenter.quotaMetrics(
            provider: provider,
            snapshot: snapshot,
            language: .en,
            localization: Self.localization
        )

        XCTAssertEqual(metrics.first?.title, "Current Plan")
    }

    private static let localization = MenuQuotaLocalization(
        quotaFiveHour: "5h",
        quotaWeekly: "Weekly",
        allModels: "All models",
        sonnetOnly: "Sonnet only",
        claudeDesign: "Claude Design",
        session: "Session",
        monthly: "Monthly",
        currentPlan: "Current Plan",
        autocomplete: "Autocomplete",
        dollarBalance: "Dollar Balance"
    )
}
