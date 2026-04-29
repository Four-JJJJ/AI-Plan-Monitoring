import XCTest
@testable import AIPlanMonitor

final class SettingsViewQuotaDisplayTests: XCTestCase {
    func testResolvedOfficialMonitoringProviderPrefersConfiguredClaudeProvider() {
        var claude = ProviderDescriptor.defaultOfficialClaude()
        claude.officialConfig?.quotaDisplayMode = .remaining

        let resolved = SettingsView.resolvedOfficialMonitoringProvider(
            type: .claude,
            providers: [claude]
        )

        XCTAssertFalse(resolved.displaysUsedQuota)
    }

    func testResolvedOfficialMonitoringProviderFallsBackToClaudeDefaultWhenMissing() {
        let resolved = SettingsView.resolvedOfficialMonitoringProvider(
            type: .claude,
            providers: []
        )

        XCTAssertTrue(resolved.displaysUsedQuota)
    }

    func testQuotaMetricPercentsKeepDisplayAndHealthSeparateInUsedMode() {
        let window = UsageQuotaWindow(
            id: "claude-session",
            title: "5h limit",
            remainingPercent: 71,
            usedPercent: 29,
            resetAt: nil,
            kind: .session
        )

        let percents = SettingsView.quotaMetricPercents(
            for: window,
            displaysUsedQuota: true
        )

        XCTAssertEqual(percents.displayPercent, 29, accuracy: 0.0001)
        XCTAssertEqual(percents.healthPercent, 71, accuracy: 0.0001)
    }

    func testOfficialMonitoringHealthStatusUsesRemainingHealthWhenDisplayModeIsUsed() {
        let snapshot = UsageSnapshot(
            source: "claude-official",
            status: .ok,
            remaining: 71,
            used: 29,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "ok",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "claude-session",
                    title: "5h limit",
                    remainingPercent: 71,
                    usedPercent: 29,
                    resetAt: nil,
                    kind: .session
                )
            ],
            sourceLabel: "API"
        )

        let status = SettingsView.officialMonitoringHealthStatus(
            snapshot: snapshot,
            healthPercents: [71]
        )

        XCTAssertEqual(status, .sufficient)
    }

    func testOfficialMonitoringHealthStatusKeepsRemainingThresholdBehavior() {
        let snapshot = UsageSnapshot(
            source: "claude-official",
            status: .ok,
            remaining: 25,
            used: 75,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "ok",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "claude-session",
                    title: "5h limit",
                    remainingPercent: 25,
                    usedPercent: 75,
                    resetAt: nil,
                    kind: .session
                )
            ],
            sourceLabel: "API"
        )

        let status = SettingsView.officialMonitoringHealthStatus(
            snapshot: snapshot,
            healthPercents: [25]
        )

        XCTAssertEqual(status, .tight)
    }
}
