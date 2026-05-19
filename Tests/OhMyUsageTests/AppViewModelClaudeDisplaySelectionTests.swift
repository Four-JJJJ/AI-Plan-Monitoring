import OhMyUsageDomain
import Foundation
import XCTest
@testable import OhMyUsage

final class AppViewModelClaudeDisplaySelectionTests: XCTestCase {
    func testResolveClaudeStatusBarDisplaySlotPrefersConfiguredMonitorableSlot() {
        let profiles = [
            makeProfile(
                slotID: .a,
                email: "proxy@example.com",
                accessToken: "access-proxy",
                scopes: ["user:inference"],
                isCurrentSystemAccount: true,
                importedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            makeProfile(
                slotID: .b,
                email: "monitorable@example.com",
                accessToken: "access-monitorable",
                scopes: ["user:profile"],
                isCurrentSystemAccount: false,
                importedAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        ]
        let slots = [
            makeSlot(slotID: .a, email: "proxy@example.com", lastSeenAt: Date(timeIntervalSince1970: 1_700_000_050), isActive: true),
            makeSlot(slotID: .b, email: "monitorable@example.com", lastSeenAt: Date(timeIntervalSince1970: 1_700_000_150), isActive: false)
        ]

        let resolved = AppOfficialProfileStateCoordinator.resolveClaudeStatusBarDisplaySlotID(
            configuredSlotID: .b,
            profiles: profiles,
            slots: slots
        )

        XCTAssertEqual(resolved, .b)
    }

    func testResolveClaudeStatusBarDisplaySlotFallsBackWhenConfiguredSlotIsUnavailable() {
        let profiles = [
            makeProfile(
                slotID: .a,
                email: "older@example.com",
                accessToken: "access-a",
                scopes: ["user:profile"],
                isCurrentSystemAccount: false,
                importedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            makeProfile(
                slotID: CodexSlotID(rawValue: "C"),
                email: "newer@example.com",
                accessToken: "access-c",
                scopes: ["user:profile"],
                isCurrentSystemAccount: false,
                importedAt: Date(timeIntervalSince1970: 1_700_000_300)
            )
        ]
        let slots = [
            makeSlot(slotID: .a, email: "older@example.com", lastSeenAt: Date(timeIntervalSince1970: 1_700_000_100), isActive: false),
            makeSlot(slotID: CodexSlotID(rawValue: "C"), email: "newer@example.com", lastSeenAt: Date(timeIntervalSince1970: 1_700_000_400), isActive: false)
        ]

        let resolved = AppOfficialProfileStateCoordinator.resolveClaudeStatusBarDisplaySlotID(
            configuredSlotID: .b,
            profiles: profiles,
            slots: slots
        )

        XCTAssertEqual(resolved, CodexSlotID(rawValue: "C"))
    }

    func testVisibleClaudeMonitoringSlotIDsExcludeInferenceOnlyCurrentProfile() {
        let profiles = [
            makeProfile(
                slotID: .a,
                email: "proxy@example.com",
                accessToken: "access-proxy",
                scopes: ["user:inference"],
                isCurrentSystemAccount: true,
                importedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            makeProfile(
                slotID: .b,
                email: "monitorable@example.com",
                accessToken: "access-monitorable",
                scopes: ["user:profile"],
                isCurrentSystemAccount: false,
                importedAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        ]

        let visibleSlotIDs = AppOfficialProfileStateCoordinator.visibleClaudeMonitoringSlotIDs(profiles: profiles)

        XCTAssertEqual(visibleSlotIDs, [.b])
    }

    private func makeProfile(
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

    private func makeSlot(
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
