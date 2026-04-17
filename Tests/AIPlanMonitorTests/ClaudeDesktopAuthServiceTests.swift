import Foundation
import XCTest
@testable import AIPlanMonitor

final class ClaudeDesktopAuthServiceTests: XCTestCase {
    func testApplyCredentialsWritesCredentialFileAndKeychain() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-auth-home-\(UUID().uuidString)", isDirectory: true)
        let configDir = home.appendingPathComponent("profiles/main", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        var savedKeychain: String?

        let service = ClaudeDesktopAuthService(
            homeDirectory: { home.path },
            environment: { ["CLAUDE_CONFIG_DIR": configDir.path] },
            keychainReader: { nil },
            keychainWriter: { value in
                savedKeychain = value
                return true
            }
        )
        let credentialsJSON = sampleCredentialsJSON(accessToken: "access-a", refreshToken: "refresh-a")

        try service.applyCredentialsJSON(credentialsJSON)

        let credentialPath = configDir.appendingPathComponent(".credentials.json").path
        let written = try String(contentsOfFile: credentialPath, encoding: .utf8)
        XCTAssertEqual(written.trimmingCharacters(in: .whitespacesAndNewlines), credentialsJSON)
        XCTAssertEqual(savedKeychain, credentialsJSON)

        let attributes = try FileManager.default.attributesOfItem(atPath: credentialPath)
        let posix = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(posix, 0o600)
    }

    func testCurrentCredentialsFallsBackToKeychainWhenFileMissing() {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-auth-home-\(UUID().uuidString)", isDirectory: true)
        let expected = sampleCredentialsJSON(accessToken: "keychain-access", refreshToken: "keychain-refresh")
        let service = ClaudeDesktopAuthService(
            homeDirectory: { home.path },
            environment: { [:] },
            keychainReader: { expected },
            keychainWriter: { _ in true }
        )

        XCTAssertEqual(service.currentCredentialsJSON(), expected)
        XCTAssertEqual(
            service.currentCredentialFingerprint(),
            try? ClaudeAccountProfileStore.parseCredentialsJSON(expected).credentialFingerprint
        )
    }

    func testApplyCredentialsRejectsInvalidJSON() {
        let service = ClaudeDesktopAuthService(
            homeDirectory: { NSHomeDirectory() },
            environment: { [:] },
            keychainReader: { nil },
            keychainWriter: { _ in true }
        )

        XCTAssertThrowsError(try service.applyCredentialsJSON(#"{"accessToken":""}"#)) { error in
            guard case ClaudeDesktopAuthError.invalidCredentials = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testApplyCredentialsFailsWhenKeychainWriteFails() {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-auth-home-\(UUID().uuidString)", isDirectory: true)
        let configDir = home.appendingPathComponent(".claude", isDirectory: true)
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let service = ClaudeDesktopAuthService(
            homeDirectory: { home.path },
            environment: { ["CLAUDE_CONFIG_DIR": configDir.path] },
            keychainReader: { nil },
            keychainWriter: { _ in false }
        )

        XCTAssertThrowsError(
            try service.applyCredentialsJSON(
                sampleCredentialsJSON(accessToken: "access-fail", refreshToken: "refresh-fail")
            )
        ) { error in
            guard case ClaudeDesktopAuthError.keychainWriteFailed = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    private func sampleCredentialsJSON(accessToken: String, refreshToken: String) -> String {
        let root: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": accessToken,
                "refreshToken": refreshToken,
                "expiresAt": 4_102_444_800_000 as Double,
                "subscriptionType": "pro",
                "scopes": ["user:profile"]
            ],
            "accountId": "acc-1",
            "email": "claude@example.com"
        ]
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
