import Foundation
import XCTest
@testable import AIPlanMonitor

final class OAuthImportOrchestratorTests: XCTestCase {
    @MainActor
    func testCodexFallsBackToDeviceAuthWhenBrowserFlowFails() async {
        let recorder = CommandRecorder()
        let orchestrator = OAuthImportOrchestrator(
            commandRunner: { command, _ in
                await recorder.append(command)
                if command.provider == .codex, command.mode == .browserCallback {
                    return OAuthImportCommandResult(status: 1, timedOut: false, wasCancelled: false, stdout: "", stderr: "browser callback failed")
                }
                return OAuthImportCommandResult(status: 0, timedOut: false, wasCancelled: false, stdout: "ok", stderr: "")
            },
            credentialLoader: { provider in
                guard provider == .codex else { return nil }
                return OAuthImportCredential(
                    rawJSON: Self.sampleCodexAuthJSON(accountID: "acc-a", email: "a@example.com"),
                    fingerprint: "finger-a",
                    accountEmail: "a@example.com"
                )
            }
        )

        var phases: [OAuthImportPhase] = []
        let result = await orchestrator.importAccount(provider: .codex, slotID: .a) { state in
            phases.append(state.phase)
        }

        guard case .success(let imported) = result else {
            return XCTFail("expected success, got \(result)")
        }

        XCTAssertEqual(imported.provider, .codex)
        XCTAssertEqual(imported.mode, .deviceAuth)

        let commands = await recorder.commands()
        XCTAssertEqual(
            commands,
            [
                OAuthImportCLICommand(provider: .codex, mode: .browserCallback),
                OAuthImportCLICommand(provider: .codex, mode: .deviceAuth)
            ]
        )
        XCTAssertTrue(phases.contains(.waitingForDevice))
        XCTAssertEqual(phases.last, .succeeded)
    }

    func testClaudeFailsWhenCredentialIsMissingAfterLogin() async {
        let orchestrator = OAuthImportOrchestrator(
            commandRunner: { _, _ in
                OAuthImportCommandResult(status: 0, timedOut: false, wasCancelled: false, stdout: "ok", stderr: "")
            },
            credentialLoader: { _ in nil }
        )

        let result = await orchestrator.importAccount(provider: .claude, slotID: .a)

        guard case .failure(let error) = result else {
            return XCTFail("expected failure, got \(result)")
        }
        XCTAssertEqual(error, .missingCredential)
    }

    private static func sampleCodexAuthJSON(accountID: String, email: String) -> String {
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

private actor CommandRecorder {
    private var recordedCommands: [OAuthImportCLICommand] = []

    func append(_ command: OAuthImportCLICommand) {
        recordedCommands.append(command)
    }

    func commands() -> [OAuthImportCLICommand] {
        recordedCommands
    }
}
