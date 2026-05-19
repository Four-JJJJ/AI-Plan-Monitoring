import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

@MainActor
final class AppOfficialAccountSwitchCoordinatorTests: XCTestCase {
    func testCodexSwitchCommitsVerifiedStateAndNotifiesWithSuccessMessage() async {
        let coordinator = AppOfficialAccountSwitchCoordinator()
        let transaction = AccountSwitchTransactionCoordinator<CodexSlotID>()
        let descriptor = makeDescriptor(type: .codex)
        let snapshot = makeSnapshot(source: "codex")
        let profile = makeCodexProfile(slotID: .a)
        var committedDescriptor: ProviderDescriptor?
        var committedSnapshot: UsageSnapshot?
        var feedbacks: [CodexSwitchFeedback?] = []
        var notifications: [String] = []

        await coordinator.switchCodexProfile(
            slotID: .a,
            transactionCoordinator: transaction,
            prepare: { profile },
            apply: { _ in },
            restart: { _ in .shutdownTimedOut },
            verify: { _ in
                OfficialAccountSwitchVerificationResult(
                    descriptor: descriptor,
                    snapshot: snapshot
                )
            },
            commitVerifiedState: { descriptor, snapshot in
                committedDescriptor = descriptor
                committedSnapshot = snapshot
            },
            successMessage: { result in
                result.requiresManualRelaunch ? "manual" : "ok"
            },
            setFeedback: { feedback, _ in feedbacks.append(feedback) },
            recordVerifyError: { _, _ in XCTFail("should not record verify error") },
            notify: { notifications.append($0) },
            applyFailureMessage: { _ in "apply-failed" },
            verifyFailureMessage: { _ in "verify-failed" }
        )

        XCTAssertEqual(committedDescriptor?.id, descriptor.id)
        XCTAssertEqual(committedSnapshot?.source, snapshot.source)
        XCTAssertEqual(feedbacks.last??.message, "manual")
        XCTAssertEqual(feedbacks.last??.isError, false)
        XCTAssertEqual(notifications, ["manual"])
    }

    func testCodexSwitchPrepareFailureSetsErrorFeedback() async {
        let coordinator = AppOfficialAccountSwitchCoordinator()
        let transaction = AccountSwitchTransactionCoordinator<CodexSlotID>()
        var feedbacks: [CodexSwitchFeedback?] = []

        await coordinator.switchCodexProfile(
            slotID: .a,
            transactionCoordinator: transaction,
            prepare: {
                throw AccountSwitchTransactionUserMessageError(message: "missing")
            },
            apply: { _ in XCTFail("should not apply") },
            restart: { _ in .relaunched },
            verify: { _ in .none },
            commitVerifiedState: { _, _ in XCTFail("should not commit") },
            successMessage: { _ in "ok" },
            setFeedback: { feedback, _ in feedbacks.append(feedback) },
            recordVerifyError: { _, _ in XCTFail("should not record verify error") },
            notify: { _ in XCTFail("should not notify") },
            applyFailureMessage: { _ in "apply-failed" },
            verifyFailureMessage: { _ in "verify-failed" }
        )

        XCTAssertEqual(feedbacks.last??.message, "missing")
        XCTAssertEqual(feedbacks.last??.isError, true)
    }

    func testClaudeSwitchWithoutVerifiedSnapshotUsesLocalSuccessMessage() async {
        let coordinator = AppOfficialAccountSwitchCoordinator()
        let transaction = AccountSwitchTransactionCoordinator<CodexSlotID>()
        let profile = makeClaudeProfile(slotID: .b)
        var feedbacks: [ClaudeSwitchFeedback?] = []
        var notifications: [String] = []

        await coordinator.switchClaudeProfile(
            slotID: .b,
            transactionCoordinator: transaction,
            prepare: { profile },
            apply: { _ in },
            restart: { _ in },
            verify: { _ in .none },
            commitVerifiedState: { _, _ in XCTFail("should not commit without verified snapshot") },
            verifiedSuccessMessage: "verified",
            localSuccessMessage: "local",
            setFeedback: { feedback, _ in feedbacks.append(feedback) },
            recordVerifyError: { _, _ in XCTFail("should not record verify error") },
            notify: { notifications.append($0) },
            applyFailureMessage: { _ in "apply-failed" },
            verifyFailureMessage: { _ in "verify-failed" }
        )

        XCTAssertEqual(feedbacks.last??.message, "local")
        XCTAssertEqual(feedbacks.last??.isError, false)
        XCTAssertTrue(notifications.isEmpty)
    }

    private func makeDescriptor(type: ProviderType) -> ProviderDescriptor {
        ProviderDescriptor(
            id: "\(type.rawValue)-official",
            name: type.rawValue,
            family: .official,
            type: type,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            officialConfig: ProviderDescriptor.defaultOfficialConfig(type: type)
        )
    }

    private func makeSnapshot(source: String) -> UsageSnapshot {
        UsageSnapshot(
            source: source,
            status: .ok,
            remaining: 75,
            used: 25,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "ok",
            sourceLabel: source,
            accountLabel: "user@example.com"
        )
    }

    private func makeCodexProfile(slotID: CodexSlotID) -> CodexAccountProfile {
        CodexAccountProfile(
            slotID: slotID,
            displayName: "Codex \(slotID.rawValue)",
            note: nil,
            authJSON: "{}",
            accountId: nil,
            accountEmail: nil,
            accountSubject: nil,
            tenantKey: nil,
            identityKey: nil,
            credentialFingerprint: nil,
            lastImportedAt: Date(timeIntervalSince1970: 1),
            isCurrentSystemAccount: false
        )
    }

    private func makeClaudeProfile(slotID: CodexSlotID) -> ClaudeAccountProfile {
        ClaudeAccountProfile(
            slotID: slotID,
            displayName: "Claude \(slotID.rawValue)",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: "{}",
            accountId: nil,
            accountEmail: nil,
            credentialFingerprint: nil,
            lastImportedAt: Date(timeIntervalSince1970: 1),
            isCurrentSystemAccount: false
        )
    }
}
