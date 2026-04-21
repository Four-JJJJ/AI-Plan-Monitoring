import Foundation
import XCTest
@testable import AIPlanMonitor

final class CodexDesktopAuthServiceTests: XCTestCase {
    func testApplyProfileWritesAuthFileAndKeychain() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-auth-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let authPath = directory.appendingPathComponent("auth.json").path
        var savedKeychain: String?

        let service = CodexDesktopAuthService(
            homeDirectory: { directory.path },
            environment: { ["CODEX_HOME": directory.path] },
            keychainReader: { nil },
            keychainWriter: { value in
                savedKeychain = value
                return true
            }
        )
        let profile = try CodexAccountProfileStore.makeProfile(
            slotID: .a,
            displayName: "Account A",
            note: nil,
            authJSON: sampleAuthJSON(accountID: "acc-a", email: "a@example.com")
        )

        try service.applyProfile(profile)

        let written = try String(contentsOfFile: authPath, encoding: .utf8)
        XCTAssertEqual(written.trimmingCharacters(in: .whitespacesAndNewlines), profile.authJSON)
        XCTAssertEqual(savedKeychain, profile.authJSON)
    }

    private func sampleAuthJSON(accountID: String, email: String) -> String {
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
