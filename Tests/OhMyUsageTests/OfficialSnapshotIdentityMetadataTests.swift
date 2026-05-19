import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class OfficialSnapshotIdentityMetadataTests: XCTestCase {
    func testCodexMetadataExtractsTeamLabelIdentityAndSlot() {
        let snapshot = UsageSnapshot(
            source: "codex-official",
            status: .ok,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Codex",
            accountLabel: nil,
            rawMeta: [
                "codex.accountId": "team-a",
                "codex.teamId": "team-a",
                "codex.accountLabel": "a@example.com",
                "codex.identityKey": "tenant|subject-a",
                "codex.slotID": "B",
                "codex.isActive": "true"
            ]
        )

        let metadata = OfficialSnapshotIdentityMetadata.codex(from: snapshot)

        XCTAssertEqual(metadata.accountID, "team-a")
        XCTAssertEqual(metadata.teamID, "team-a")
        XCTAssertEqual(metadata.accountLabel, "a@example.com")
        XCTAssertEqual(metadata.identityKey, "tenant|subject-a")
        XCTAssertEqual(metadata.slotID, .b)
        XCTAssertEqual(metadata.isActive, true)
    }

    func testClaudeMetadataPrefersSnapshotAccountLabelAndConfigDir() {
        let snapshot = UsageSnapshot(
            source: "claude-official",
            status: .ok,
            remaining: 70,
            used: 30,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Claude",
            accountLabel: "snapshot@example.com",
            rawMeta: [
                "claude.accountId": "acc-b",
                "claude.accountLabel": "raw@example.com",
                "claude.configDir": "/tmp/claude-b",
                "claude.slotID": "A",
                "claude.isActive": "false"
            ]
        )

        let metadata = OfficialSnapshotIdentityMetadata.claude(from: snapshot)

        XCTAssertEqual(metadata.accountID, "acc-b")
        XCTAssertEqual(metadata.accountLabel, "snapshot@example.com")
        XCTAssertEqual(metadata.configDir, "/tmp/claude-b")
        XCTAssertEqual(metadata.slotID, .a)
        XCTAssertEqual(metadata.isActive, false)
    }
}
