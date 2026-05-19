import OhMyUsageDomain
import Foundation
import XCTest
@testable import OhMyUsage

@MainActor
final class AppOfficialProfileDisplayCoordinatorTests: XCTestCase {
    func testUpdateClaudeStatusBarDisplaySelectionNormalizesAndComputesNotifyFlags() {
        let coordinator = AppOfficialProfileDisplayCoordinator()
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

        let outcome = coordinator.updateClaudeStatusBarDisplaySelection(
            requestedSlotID: .a,
            configuredSlotID: nil,
            profiles: profiles,
            slots: slots
        )

        XCTAssertNil(outcome.normalizedConfiguredSlotID)
        XCTAssertEqual(outcome.previousResolvedDisplaySlotID, .b)
        XCTAssertEqual(outcome.resolvedDisplaySlotID, .b)
        XCTAssertFalse(outcome.shouldPersist)
        XCTAssertFalse(outcome.shouldNotify)
    }

    func testClaudeStatusBarDisplayPrefetchActionDistinguishesNotifyOnlyAndRefresh() {
        let coordinator = AppOfficialProfileDisplayCoordinator()
        let descriptor = ProviderDescriptor.defaultOfficialClaude()
        let currentProfile = makeProfile(
            slotID: .a,
            email: "current@example.com",
            accessToken: "access-a",
            scopes: ["user:profile"],
            isCurrentSystemAccount: true,
            importedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let secondaryProfile = makeProfile(
            slotID: .b,
            email: "secondary@example.com",
            accessToken: "access-b",
            scopes: ["user:profile"],
            isCurrentSystemAccount: false,
            importedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        XCTAssertEqual(
            coordinator.claudeStatusBarDisplayPrefetchAction(
                slotID: .a,
                descriptor: descriptor,
                profiles: [currentProfile, secondaryProfile]
            ),
            .notifyOnly
        )
        XCTAssertEqual(
            coordinator.claudeStatusBarDisplayPrefetchAction(
                slotID: .b,
                descriptor: descriptor,
                profiles: [currentProfile, secondaryProfile]
            ),
            .refresh(slotID: .b)
        )
    }

    func testClaudeStatusBarDisplaySnapshotPrefersResolvedSlotSnapshot() {
        let coordinator = AppOfficialProfileDisplayCoordinator()
        let slotSnapshot = UsageSnapshot(
            source: "claude-slot",
            status: .ok,
            remaining: 88,
            used: 12,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Slot"
        )
        let providerSnapshot = UsageSnapshot(
            source: "claude-provider",
            status: .ok,
            remaining: 55,
            used: 45,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Provider"
        )
        let slotViewModels = [
            ClaudeSlotViewModel(
                slotID: .b,
                title: "Claude B",
                snapshot: slotSnapshot,
                isActive: false,
                lastSeenAt: Date(),
                displayName: "Claude B",
                note: nil
            )
        ]

        let resolved = coordinator.claudeStatusBarDisplaySnapshot(
            resolvedSlotID: .b,
            slotViewModels: slotViewModels,
            providerSnapshot: providerSnapshot
        )

        XCTAssertEqual(resolved?.source, "claude-slot")
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
