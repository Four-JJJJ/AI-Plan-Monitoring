import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class UsageQuotaWindowResetMetadataTests: XCTestCase {
    func testLegacySnapshotDecodeDefaultsModernFields() throws {
        let json = """
        {
          "source": "codex-official",
          "status": "ok",
          "remaining": 75,
          "used": 25,
          "limit": 100,
          "unit": "%",
          "updatedAt": "2026-04-10T12:00:00Z",
          "note": "ok"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(UsageSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.fetchHealth, .ok)
        XCTAssertEqual(snapshot.valueFreshness, .live)
        XCTAssertEqual(snapshot.sourceLabel, "")
        XCTAssertEqual(snapshot.quotaWindows, [])
        XCTAssertEqual(snapshot.extras, [:])
        XCTAssertEqual(snapshot.rawMeta, [:])
    }

    func testLegacyWindowDecodeDefaultsResetMetadata() throws {
        let json = """
        {
          "id": "session",
          "title": "5h",
          "remainingPercent": 75,
          "usedPercent": 25,
          "resetAt": "2026-04-10T12:00:00Z",
          "kind": "session"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let window = try decoder.decode(UsageQuotaWindow.self, from: Data(json.utf8))

        XCTAssertEqual(window.resetSource, .unknown)
        XCTAssertEqual(window.confidence, .unknown)
        XCTAssertNil(window.observedAt)
        XCTAssertNil(window.windowIdentity)
    }

    func testSnapshotDecodeInfersMetadataForEmbeddedLegacyWindow() throws {
        let json = """
        {
          "source": "codex-official",
          "status": "ok",
          "remaining": 75,
          "used": 25,
          "limit": 100,
          "unit": "%",
          "updatedAt": "2026-04-10T12:00:00Z",
          "note": "ok",
          "sourceLabel": "API",
          "quotaWindows": [
            {
              "id": "session",
              "title": "5h",
              "remainingPercent": 75,
              "usedPercent": 25,
              "resetAt": "2026-04-10T13:00:00Z",
              "kind": "session"
            }
          ]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(UsageSnapshot.self, from: Data(json.utf8))

        let window = try XCTUnwrap(snapshot.quotaWindows.first)
        XCTAssertEqual(window.resetSource, .official)
        XCTAssertEqual(window.confidence, .confirmed)
        XCTAssertEqual(window.observedAt, snapshot.updatedAt)
        XCTAssertEqual(window.windowIdentity, "session:1775826000")
    }

    func testSnapshotInfersOfficialConfirmedMetadataForLiveAPIWindows() {
        let updatedAt = Date(timeIntervalSince1970: 100)
        let resetAt = Date(timeIntervalSince1970: 1_000)
        let snapshot = UsageSnapshot(
            source: "codex-official",
            status: .ok,
            valueFreshness: .live,
            remaining: 75,
            used: 25,
            limit: 100,
            unit: "%",
            updatedAt: updatedAt,
            note: "ok",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "session",
                    title: "5h",
                    remainingPercent: 75,
                    usedPercent: 25,
                    resetAt: resetAt,
                    kind: .session
                )
            ],
            sourceLabel: "API"
        )

        let window = snapshot.quotaWindows[0]
        XCTAssertEqual(window.resetSource, .official)
        XCTAssertEqual(window.confidence, .confirmed)
        XCTAssertEqual(window.observedAt, updatedAt)
        XCTAssertEqual(window.windowIdentity, "session:1000")
    }

    func testSnapshotMarksCachedFallbackWindowAsStale() {
        let snapshot = UsageSnapshot(
            source: "codex-official",
            status: .warning,
            valueFreshness: .cachedFallback,
            remaining: 75,
            used: 25,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 100),
            note: "cached",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "session",
                    title: "5h",
                    remainingPercent: 75,
                    usedPercent: 25,
                    resetAt: Date(timeIntervalSince1970: 1_000),
                    kind: .session
                )
            ],
            sourceLabel: "API"
        )

        XCTAssertEqual(snapshot.quotaWindows[0].resetSource, .official)
        XCTAssertEqual(snapshot.quotaWindows[0].confidence, .stale)
    }
}
