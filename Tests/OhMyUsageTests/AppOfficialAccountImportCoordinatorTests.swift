import Foundation
import XCTest
@testable import OhMyUsage

@MainActor
final class AppOfficialAccountImportCoordinatorTests: XCTestCase {
    func testStartCodexImportReturnsNilWhenTaskAlreadyRunning() {
        let coordinator = AppOfficialAccountImportCoordinator()
        let existingTask = Task<Void, Never> {}

        let task = coordinator.startCodexImport(
            slotID: .a,
            currentTask: existingTask,
            currentState: { nil },
            importAccount: { _, _, _ in
                XCTFail("should not invoke import when task already exists")
                return .failure(.cancelled)
            },
            matchingProfile: { _ in nil },
            saveImportedProfile: { _, _, _ in
                XCTFail("should not save when task already exists")
                return OAuthImportSaveOutcome(slotID: .a, detail: "")
            },
            setState: { _ in },
            clearTask: {}
        )

        XCTAssertNil(task)
        existingTask.cancel()
    }

    func testStartCodexImportUsesMatchedProfileSlotOnSuccess() async {
        let coordinator = AppOfficialAccountImportCoordinator()
        let matchedProfile = CodexAccountProfile(
            slotID: .b,
            displayName: "Codex B",
            note: "work",
            authJSON: sampleCodexAuthJSON(accountID: "acc-b", email: "b@example.com"),
            accountId: "acc-b",
            accountEmail: "b@example.com",
            accountSubject: "subject-b",
            tenantKey: "tenant",
            identityKey: "tenant|subject-b",
            credentialFingerprint: "finger-b",
            lastImportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isCurrentSystemAccount: false
        )
        var finalState: OAuthImportState?
        var clearCalled = false

        let task = coordinator.startCodexImport(
            slotID: .a,
            currentTask: nil,
            currentState: { finalState },
            importAccount: { provider, slotID, stateHandler in
                stateHandler?(
                    OAuthImportState(
                        provider: provider,
                        slotID: slotID,
                        mode: .browserCallback,
                        phase: .verifying,
                        detail: nil,
                        startedAt: Date(timeIntervalSince1970: 100),
                        updatedAt: Date(timeIntervalSince1970: 101)
                    )
                )
                return .success(
                    OAuthImportResult(
                        provider: .codex,
                        slotID: slotID,
                        mode: .deviceAuth,
                        rawCredentialJSON: self.sampleCodexAuthJSON(accountID: "acc-b", email: "b@example.com"),
                        accountEmail: "b@example.com"
                    )
                )
            },
            matchingProfile: { _ in matchedProfile },
            saveImportedProfile: { imported, originalSlotID, existing in
                XCTAssertEqual(imported.provider, .codex)
                XCTAssertEqual(originalSlotID, .a)
                XCTAssertEqual(existing?.slotID, .b)
                return OAuthImportSaveOutcome(slotID: existing?.slotID ?? originalSlotID, detail: "saved")
            },
            setState: { finalState = $0 },
            clearTask: { clearCalled = true }
        )

        await task?.value

        XCTAssertEqual(finalState?.phase, .succeeded)
        XCTAssertEqual(finalState?.mode, .deviceAuth)
        XCTAssertEqual(finalState?.slotID, .b)
        XCTAssertEqual(finalState?.detail, "saved")
        XCTAssertTrue(clearCalled)
    }

    func testStartClaudeImportPreservesCurrentModeAndStartedAtOnFailure() async {
        let coordinator = AppOfficialAccountImportCoordinator()
        let originalStart = Date(timeIntervalSince1970: 500)
        var finalState = OAuthImportState(
            provider: .claude,
            slotID: .a,
            mode: .deviceAuth,
            phase: .waitingForDevice,
            detail: nil,
            startedAt: originalStart,
            updatedAt: Date(timeIntervalSince1970: 501)
        )

        let task = coordinator.startClaudeImport(
            slotID: .a,
            currentTask: nil,
            currentState: { finalState },
            importAccount: { _, _, _ in
                .failure(.commandFailed("network unreachable"))
            },
            matchingProfile: { _ in nil },
            saveImportedProfile: { _, _, _ in
                XCTFail("should not save on failure")
                return OAuthImportSaveOutcome(slotID: .a, detail: "")
            },
            setState: { finalState = $0 ?? finalState },
            clearTask: {}
        )

        await task?.value

        XCTAssertEqual(finalState.phase, .failed)
        XCTAssertEqual(finalState.mode, .deviceAuth)
        XCTAssertEqual(finalState.startedAt, originalStart)
        XCTAssertEqual(finalState.detail, "network unreachable")
    }

    private func sampleCodexAuthJSON(accountID: String, email: String) -> String {
        let payload = Data(#"{"email":"\#(email)"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return #"""
        {
          "tokens": {
            "access_token": "access-token-\#(accountID)",
            "refresh_token": "refresh-token-\#(accountID)",
            "account_id": "\#(accountID)",
            "id_token": "header.\#(payload).signature"
          }
        }
        """#
    }
}
