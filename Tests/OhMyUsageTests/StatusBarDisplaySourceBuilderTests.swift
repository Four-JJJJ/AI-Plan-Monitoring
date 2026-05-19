import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class StatusBarDisplaySourceBuilderTests: XCTestCase {
    func testCodexPrefersActiveSlotSnapshotOverProviderSnapshot() {
        let provider = makeProvider(id: "codex-official", name: "Codex", family: .official, type: .codex)
        let providerSnapshot = makeSnapshot(source: "provider", accountLabel: "provider@example.com")
        let activeSnapshot = makeSnapshot(source: "active", accountLabel: "active@example.com")

        let source = StatusBarDisplaySourceBuilder.displaySource(
            for: provider,
            style: .iconPercent,
            providerSnapshots: [provider.id: providerSnapshot],
            codexActiveSnapshot: activeSnapshot,
            claudeDisplaySnapshot: nil,
            thirdPartyBarPercent: nil
        )

        XCTAssertEqual(source.snapshot?.source, "active")
        XCTAssertEqual(source.snapshot?.accountLabel, "active@example.com")
    }

    func testCodexFallsBackToProviderSnapshotWhenActiveSlotIsPlaceholder() {
        let provider = makeProvider(id: "codex-official", name: "Codex", family: .official, type: .codex)
        let providerSnapshot = makeSnapshot(source: "provider", accountLabel: "provider@example.com")
        let placeholderSnapshot = makeSnapshot(
            source: "codex-placeholder-b",
            accountLabel: "new@example.com",
            rawMeta: ["codex.menuPlaceholder": "true"]
        )

        let source = StatusBarDisplaySourceBuilder.displaySource(
            for: provider,
            style: .iconPercent,
            providerSnapshots: [provider.id: providerSnapshot],
            codexActiveSnapshot: placeholderSnapshot,
            claudeDisplaySnapshot: nil,
            thirdPartyBarPercent: nil
        )

        XCTAssertEqual(source.snapshot?.source, "provider")
        XCTAssertEqual(source.snapshot?.accountLabel, "provider@example.com")
    }

    func testClaudeOfficialUsesDisplaySnapshotInsteadOfProviderSnapshot() {
        let provider = makeProvider(id: "claude-official", name: "Claude", family: .official, type: .claude)
        let providerSnapshot = makeSnapshot(source: "provider", accountLabel: "provider@example.com")
        let displaySnapshot = makeSnapshot(source: "display", accountLabel: "display@example.com")

        let source = StatusBarDisplaySourceBuilder.displaySource(
            for: provider,
            style: .iconPercent,
            providerSnapshots: [provider.id: providerSnapshot],
            codexActiveSnapshot: nil,
            claudeDisplaySnapshot: displaySnapshot,
            thirdPartyBarPercent: nil
        )

        XCTAssertEqual(source.snapshot?.source, "display")
        XCTAssertEqual(source.snapshot?.accountLabel, "display@example.com")
    }

    func testThirdPartyBaselinePercentOnlyAppliesToBarStyleRemainingDisplay() {
        let provider = makeProvider(id: "relay-third-party", name: "Relay", family: .thirdParty, type: .relay)
        let source = StatusBarDisplaySourceBuilder.displaySource(
            for: provider,
            style: .barNamePercent,
            providerSnapshots: [:],
            codexActiveSnapshot: nil,
            claudeDisplaySnapshot: nil,
            thirdPartyBarPercent: 62
        )
        let iconStyleSource = StatusBarDisplaySourceBuilder.displaySource(
            for: provider,
            style: .iconPercent,
            providerSnapshots: [:],
            codexActiveSnapshot: nil,
            claudeDisplaySnapshot: nil,
            thirdPartyBarPercent: 62
        )

        XCTAssertEqual(source.thirdPartyBarPercent, 62)
        XCTAssertNil(iconStyleSource.thirdPartyBarPercent)
    }

    private func makeProvider(
        id: String,
        name: String,
        family: ProviderFamily,
        type: ProviderType
    ) -> ProviderDescriptor {
        ProviderDescriptor(
            id: id,
            name: name,
            family: family,
            type: type,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            officialConfig: family == .official ? ProviderDescriptor.defaultOfficialConfig(type: type) : nil
        )
    }

    private func makeSnapshot(
        source: String,
        accountLabel: String,
        rawMeta: [String: String] = [:]
    ) -> UsageSnapshot {
        UsageSnapshot(
            source: source,
            status: .ok,
            remaining: 70,
            used: 30,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "ok",
            sourceLabel: source,
            accountLabel: accountLabel,
            rawMeta: rawMeta
        )
    }
}
