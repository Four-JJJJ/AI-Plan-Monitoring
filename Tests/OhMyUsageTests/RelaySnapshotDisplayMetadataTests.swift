import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class RelaySnapshotDisplayMetadataTests: XCTestCase {
    func testExtractsRequestCountTokenPlanRecoveryQuotaValueAndAuthSource() {
        let snapshot = UsageSnapshot(
            source: "relay",
            status: .ok,
            remaining: 90,
            used: 10,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Relay",
            authSourceLabel: "Browser",
            rawMeta: [
                "relay.adapterID": "generic-newapi",
                "account.requestCount": "42",
                "account.tokenPlanCurrentPeriodEnd": "2026-05-09T00:00:00Z",
                "relay.recovery.succeeded": "true",
                "relay.recovery.source": "cookie refresh",
                "relay.recovery.at": "2026-05-08T12:00:00Z",
                "account.quotaValueText.window-a": "1 / 2"
            ]
        )

        let metadata = RelaySnapshotDisplayMetadata(snapshot: snapshot)

        XCTAssertEqual(metadata.resolvedAdapterID, "generic-newapi")
        XCTAssertEqual(metadata.requestCount, 42)
        XCTAssertEqual(metadata.tokenPlanCurrentPeriodEnd, "2026-05-09T00:00:00Z")
        XCTAssertEqual(metadata.authSource, "Browser")
        XCTAssertEqual(metadata.quotaValueText(for: "window-a"), "1 / 2")
        XCTAssertEqual(metadata.recovery?.source, "cookie refresh")
        XCTAssertNotNil(metadata.recovery?.recoveredAt)
    }

    func testFallsBackToConfiguredAdapterIDAndSecondaryKeys() {
        let snapshot = UsageSnapshot(
            source: "relay",
            status: .ok,
            remaining: 90,
            used: 10,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Relay",
            rawMeta: [
                "token.authSource": "Manual",
                "tokenPlanCurrentPeriodEnd": "2026-05-10T00:00:00Z",
                "quotaValueText.window-a": "fallback text"
            ]
        )

        let metadata = RelaySnapshotDisplayMetadata(
            snapshot: snapshot,
            fallbackAdapterID: "fallback-adapter"
        )

        XCTAssertEqual(metadata.resolvedAdapterID, "fallback-adapter")
        XCTAssertEqual(metadata.authSource, "Manual")
        XCTAssertEqual(metadata.tokenPlanCurrentPeriodEnd, "2026-05-10T00:00:00Z")
        XCTAssertEqual(metadata.quotaValueText(for: "window-a"), "fallback text")
    }
}
