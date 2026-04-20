import Foundation
import XCTest
@testable import AIPlanMonitor

final class ClaudePrefetchPlannerTests: XCTestCase {
    func testSelectCandidatesSkipsUnchangedIdentityAndRespectsMaxConcurrency() {
        let now = Date()
        let slotC = CodexSlotID(rawValue: "C")
        let profiles = [
            sampleProfile(slot: .a, accountID: "acc-a", email: "a@example.com", fingerprint: "fp-a", lastImportedAt: now),
            sampleProfile(slot: .b, accountID: "acc-b", email: "b@example.com", fingerprint: "fp-b", lastImportedAt: now.addingTimeInterval(-10)),
            sampleProfile(slot: slotC, accountID: "acc-c", email: "c@example.com", fingerprint: "fp-c", lastImportedAt: now.addingTimeInterval(-20))
        ]

        let attempted: [CodexSlotID: String] = [
            .b: ClaudePrefetchPlanner.identityKey(for: profiles[1])
        ]
        let candidates = ClaudePrefetchPlanner.selectCandidates(
            profiles: profiles,
            preferredActiveSlotID: .a,
            activeRuntimeSlotIDs: [],
            inFlightSlots: [slotC],
            attemptedIdentity: attempted,
            maxNewTasks: 2
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testSelectCandidatesReturnsNewestEligibleProfiles() {
        let now = Date()
        let slotC = CodexSlotID(rawValue: "C")
        let profileA = sampleProfile(
            slot: .a,
            accountID: "acc-a",
            email: "a@example.com",
            fingerprint: "fp-a",
            lastImportedAt: now.addingTimeInterval(-10)
        )
        let profileB = sampleProfile(
            slot: .b,
            accountID: nil,
            email: "b@example.com",
            fingerprint: "fp-b",
            lastImportedAt: now
        )
        let profileC = sampleProfile(
            slot: slotC,
            accountID: nil,
            email: "c@example.com",
            fingerprint: "fp-c",
            lastImportedAt: now.addingTimeInterval(-20)
        )

        let candidates = ClaudePrefetchPlanner.selectCandidates(
            profiles: [profileA, profileB, profileC],
            preferredActiveSlotID: nil,
            activeRuntimeSlotIDs: [],
            inFlightSlots: [],
            attemptedIdentity: [:],
            maxNewTasks: 2
        )

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.map { $0.slotID.rawValue }, ["B", "A"])
        XCTAssertEqual(candidates[0].identityKey, ClaudePrefetchPlanner.identityKey(for: profileB))
        XCTAssertEqual(candidates[1].identityKey, ClaudePrefetchPlanner.identityKey(for: profileA))
    }

    func testIdentityKeyPrefersAccountIDThenEmailAndConfigThenFingerprint() {
        let withAccountID = sampleProfile(
            slot: .a,
            accountID: "Account-Upper",
            email: "mail@example.com",
            fingerprint: "fp-a",
            configDir: "/tmp/claude-a"
        )
        XCTAssertEqual(
            ClaudePrefetchPlanner.identityKey(for: withAccountID),
            "account:account-upper"
        )

        let withEmail = sampleProfile(
            slot: .b,
            accountID: nil,
            email: "mail@example.com",
            fingerprint: "fp-b",
            configDir: "/tmp/claude-b"
        )
        XCTAssertTrue(ClaudePrefetchPlanner.identityKey(for: withEmail).hasPrefix("email:mail@example.com|config:"))

        let slotC = CodexSlotID(rawValue: "C")
        let withFingerprintOnly = sampleProfile(
            slot: slotC,
            accountID: nil,
            email: nil,
            fingerprint: "FP-C"
        )
        XCTAssertEqual(
            ClaudePrefetchPlanner.identityKey(for: withFingerprintOnly),
            "fingerprint:fp-c"
        )
    }

    private func sampleProfile(
        slot: CodexSlotID,
        accountID: String?,
        email: String?,
        fingerprint: String?,
        configDir: String? = nil,
        lastImportedAt: Date = Date()
    ) -> ClaudeAccountProfile {
        ClaudeAccountProfile(
            slotID: slot,
            displayName: "Claude \(slot.rawValue)",
            source: .configDir,
            configDir: configDir,
            credentialsJSON: nil,
            accountId: accountID,
            accountEmail: email,
            credentialFingerprint: fingerprint,
            lastImportedAt: lastImportedAt,
            isCurrentSystemAccount: false
        )
    }
}
