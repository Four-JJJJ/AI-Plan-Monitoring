import OhMyUsageDomain
import Foundation
import XCTest
@testable import OhMyUsage

final class AppOfficialProfileStateCoordinatorTests: XCTestCase {
    func testMergedCodexSlotsForMenuPrefersCurrentProfileAsSingleActiveSlot() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let profiles = [
            CodexAccountProfile(
                slotID: .a,
                displayName: "Codex A",
                note: nil,
                authJSON: "{\"access_token\":\"a\"}",
                accountId: "team-a",
                accountEmail: "a@example.com",
                accountSubject: "subject-a",
                tenantKey: "tenant",
                identityKey: "tenant|subject-a",
                credentialFingerprint: "fingerprint-a",
                lastImportedAt: now,
                isCurrentSystemAccount: false
            ),
            CodexAccountProfile(
                slotID: .b,
                displayName: "Codex B",
                note: nil,
                authJSON: "{\"access_token\":\"b\"}",
                accountId: "team-b",
                accountEmail: "b@example.com",
                accountSubject: "subject-b",
                tenantKey: "tenant",
                identityKey: "tenant|subject-b",
                credentialFingerprint: "fingerprint-b",
                lastImportedAt: now.addingTimeInterval(60),
                isCurrentSystemAccount: true
            )
        ]
        let slots = [
            makeCodexSlot(slotID: .a, email: "a@example.com", lastSeenAt: now.addingTimeInterval(10), isActive: true),
            makeCodexSlot(slotID: .b, email: "b@example.com", lastSeenAt: now.addingTimeInterval(20), isActive: true)
        ]

        let merged = AppOfficialProfileStateCoordinator.mergedCodexSlotsForMenu(
            profiles: profiles,
            slots: slots
        )

        XCTAssertEqual(merged.filter(\.isActive).map(\.slotID), [.b])
    }

    func testMarkClaudeSnapshotActiveBackfillsMatchedProfileMetadata() {
        let profile = ClaudeAccountProfile(
            slotID: .b,
            displayName: "Claude B",
            note: nil,
            source: .configDir,
            configDir: "/tmp/claude-b",
            credentialsJSON: "{\"claudeAiOauth\":{\"accessToken\":\"token-b\",\"scopes\":[\"user:profile\"]}}",
            accountId: "acc-b",
            accountEmail: "b@example.com",
            credentialFingerprint: "fingerprint-b",
            lastImportedAt: Date(timeIntervalSince1970: 1_700_000_120),
            isCurrentSystemAccount: true
        )
        let snapshot = UsageSnapshot(
            source: "claude-official",
            status: .ok,
            remaining: 70,
            used: 30,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_180),
            note: "ok",
            sourceLabel: "Claude",
            accountLabel: nil,
            rawMeta: [:]
        )

        let marked = AppOfficialProfileStateCoordinator.markClaudeSnapshotActive(
            snapshot,
            profiles: [profile]
        )

        XCTAssertEqual(marked.rawMeta["claude.slotID"], "B")
        XCTAssertEqual(marked.rawMeta["claude.accountId"], "acc-b")
        XCTAssertEqual(marked.rawMeta["claude.configDir"], "/tmp/claude-b")
        XCTAssertEqual(marked.rawMeta["claude.accountLabel"], "b@example.com")
        XCTAssertEqual(marked.accountLabel, "b@example.com")
        XCTAssertEqual(marked.rawMeta["claude.isActive"], "true")
    }

    func testEvaluateClaudeProfileSyncClearsUnavailableConfiguredDisplaySlot() {
        let proxyProfile = makeClaudeProfile(
            slotID: .a,
            email: "proxy@example.com",
            accessToken: "proxy-token",
            scopes: ["user:inference"],
            isCurrentSystemAccount: true,
            importedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let visibleProfile = makeClaudeProfile(
            slotID: .b,
            email: "visible@example.com",
            accessToken: "visible-token",
            scopes: ["user:profile"],
            isCurrentSystemAccount: false,
            importedAt: Date(timeIntervalSince1970: 1_700_000_300)
        )

        let evaluation = AppOfficialProfileStateCoordinator.evaluateClaudeProfileSync(
            previousProfiles: [visibleProfile],
            latestProfiles: [proxyProfile, visibleProfile],
            slots: [makeClaudeSlot(slotID: .b, email: "visible@example.com", lastSeenAt: Date(timeIntervalSince1970: 1_700_000_350), isActive: false)],
            configuredDisplaySlotID: .a
        )

        XCTAssertNil(evaluation.normalizedConfiguredDisplaySlotID)
        XCTAssertEqual(evaluation.resolvedDisplaySlotID, .b)
        XCTAssertTrue(evaluation.didProfileIdentityChange)
    }

    private func makeCodexSlot(
        slotID: CodexSlotID,
        email: String,
        lastSeenAt: Date,
        isActive: Bool
    ) -> CodexAccountSlot {
        CodexAccountSlot(
            slotID: slotID,
            accountKey: "email:\(email)",
            displayName: "Codex \(slotID.rawValue)",
            lastSnapshot: UsageSnapshot(
                source: "codex-official",
                status: .ok,
                remaining: 80,
                used: 20,
                limit: 100,
                unit: "%",
                updatedAt: lastSeenAt,
                note: "ok",
                sourceLabel: "Codex",
                accountLabel: email,
                rawMeta: [
                    "codex.slotID": slotID.rawValue,
                    "codex.accountLabel": email
                ]
            ),
            lastSeenAt: lastSeenAt,
            isActive: isActive
        )
    }

    private func makeClaudeProfile(
        slotID: CodexSlotID,
        email: String,
        accessToken: String,
        scopes: [String],
        isCurrentSystemAccount: Bool,
        importedAt: Date
    ) -> ClaudeAccountProfile {
        ClaudeAccountProfile(
            slotID: slotID,
            displayName: "Claude \(slotID.rawValue)",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: sampleCredentialsJSON(email: email, accessToken: accessToken, scopes: scopes),
            accountId: "acc-\(slotID.rawValue.lowercased())",
            accountEmail: email,
            credentialFingerprint: ClaudeAccountProfileStore.credentialFingerprint(for: accessToken),
            lastImportedAt: importedAt,
            isCurrentSystemAccount: isCurrentSystemAccount
        )
    }

    private func makeClaudeSlot(
        slotID: CodexSlotID,
        email: String,
        lastSeenAt: Date,
        isActive: Bool
    ) -> ClaudeAccountSlot {
        ClaudeAccountSlot(
            slotID: slotID,
            accountKey: "email:\(email)",
            displayName: "Claude \(slotID.rawValue)",
            lastSnapshot: UsageSnapshot(
                source: "claude-official",
                status: .ok,
                remaining: 80,
                used: 20,
                limit: 100,
                unit: "%",
                updatedAt: lastSeenAt,
                note: "ok",
                sourceLabel: "Profile",
                accountLabel: email,
                rawMeta: [
                    "claude.slotID": slotID.rawValue,
                    "claude.accountLabel": email
                ]
            ),
            lastSeenAt: lastSeenAt,
            isActive: isActive
        )
    }

    private func sampleCredentialsJSON(email: String, accessToken: String, scopes: [String]) -> String {
        let root: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": accessToken,
                "refreshToken": "refresh-\(accessToken)",
                "subscriptionType": "pro",
                "scopes": scopes
            ],
            "accountId": "acc-\(accessToken)",
            "email": email
        ]
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
