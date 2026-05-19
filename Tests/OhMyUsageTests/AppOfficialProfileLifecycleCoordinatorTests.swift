import Foundation
import OhMyUsageDomain
import XCTest
import OhMyUsageApplication
@testable import OhMyUsage

@MainActor
final class AppOfficialProfileLifecycleCoordinatorTests: XCTestCase {
    func testRefreshCodexProfilesAfterManualRefreshSyncsAndSkipsActiveSlot() async {
        let coordinator = AppOfficialProfileLifecycleCoordinator()
        let runtime = CodexOfficialProfileRefreshRuntime()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let profiles = [
            makeCodexProfile(slotID: .a, email: "a@example.com", importedAt: now),
            makeCodexProfile(slotID: .b, email: "b@example.com", importedAt: now.addingTimeInterval(60))
        ]
        let slots = [
            makeCodexSlot(slotID: .a, email: "a@example.com", lastSeenAt: now, isActive: true),
            makeCodexSlot(slotID: .b, email: "b@example.com", lastSeenAt: now, isActive: false)
        ]
        var didSync = false
        var refreshed: [CodexSlotID] = []

        await coordinator.refreshCodexProfilesAfterManualRefresh(
            descriptor: makeOfficialDescriptor(type: .codex),
            slots: slots,
            runtime: runtime,
            syncProfiles: {
                didSync = true
                return profiles
            }
        ) { profile in
            refreshed.append(profile.slotID)
            return .success
        }

        XCTAssertTrue(didSync)
        XCTAssertEqual(refreshed, [.b])
    }

    func testRefreshClaudeInactiveProfilesInBackgroundSyncsAndRefreshesNextInactiveSlot() async {
        let coordinator = AppOfficialProfileLifecycleCoordinator()
        let runtime = ClaudeOfficialProfileRefreshRuntime()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let profiles = [
            makeClaudeProfile(slotID: .a, email: "a@example.com", importedAt: now),
            makeClaudeProfile(slotID: .b, email: "b@example.com", importedAt: now.addingTimeInterval(60))
        ]
        let slots = [
            makeClaudeSlot(slotID: .a, email: "a@example.com", lastSeenAt: now, isActive: true)
        ]
        var didSync = false
        var refreshed: [CodexSlotID] = []

        await coordinator.refreshClaudeInactiveProfilesInBackgroundIfNeeded(
            descriptor: makeOfficialDescriptor(type: .claude, pollIntervalSec: 30),
            slots: slots,
            runtime: runtime,
            syncProfiles: {
                didSync = true
                return profiles
            }
        ) { profile in
            refreshed.append(profile.slotID)
            return .success
        }

        XCTAssertTrue(didSync)
        XCTAssertEqual(refreshed, [.b])
    }

    func testScheduleCodexPrefetchIfNeededRefreshesMissingProfileSlot() async {
        let coordinator = AppOfficialProfileLifecycleCoordinator()
        let runtime = CodexOfficialProfileRefreshRuntime()
        let profile = makeCodexProfile(
            slotID: .a,
            email: "a@example.com",
            importedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let refreshed = expectation(description: "prefetch refresh invoked")

        coordinator.scheduleCodexPrefetchIfNeeded(
            descriptor: makeOfficialDescriptor(type: .codex),
            profiles: [profile],
            slots: [],
            runtime: runtime
        ) { candidate, _ in
            XCTAssertEqual(candidate.slotID, .a)
            refreshed.fulfill()
            return .success
        }

        await fulfillment(of: [refreshed], timeout: 1.0)
    }

    private func makeOfficialDescriptor(
        type: ProviderType,
        pollIntervalSec: Int = 60
    ) -> ProviderDescriptor {
        ProviderDescriptor(
            id: "\(type.rawValue)-official",
            name: type.rawValue,
            family: .official,
            type: type,
            enabled: true,
            pollIntervalSec: pollIntervalSec,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            officialConfig: ProviderDescriptor.defaultOfficialConfig(type: type)
        )
    }

    private func makeCodexProfile(
        slotID: CodexSlotID,
        email: String,
        importedAt: Date
    ) -> CodexAccountProfile {
        CodexAccountProfile(
            slotID: slotID,
            displayName: "Codex \(slotID.rawValue)",
            note: nil,
            authJSON: "{\"access_token\":\"\(slotID.rawValue.lowercased())\"}",
            accountId: "team-\(slotID.rawValue.lowercased())",
            accountEmail: email,
            accountSubject: "subject-\(slotID.rawValue.lowercased())",
            tenantKey: "tenant",
            identityKey: "tenant|subject-\(slotID.rawValue.lowercased())",
            credentialFingerprint: "fingerprint-\(slotID.rawValue.lowercased())",
            lastImportedAt: importedAt,
            isCurrentSystemAccount: false
        )
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
        importedAt: Date
    ) -> ClaudeAccountProfile {
        ClaudeAccountProfile(
            slotID: slotID,
            displayName: "Claude \(slotID.rawValue)",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: "{\"claudeAiOauth\":{\"accessToken\":\"token-\(slotID.rawValue.lowercased())\",\"scopes\":[\"user:profile\"]}}",
            accountId: "account-\(slotID.rawValue.lowercased())",
            accountEmail: email,
            credentialFingerprint: "fingerprint-\(slotID.rawValue.lowercased())",
            lastImportedAt: importedAt,
            isCurrentSystemAccount: slotID == .a
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
                remaining: 75,
                used: 25,
                limit: 100,
                unit: "%",
                updatedAt: lastSeenAt,
                note: "ok",
                sourceLabel: "Claude",
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
}
