import Foundation
import XCTest
@testable import AIPlanMonitor

final class ClaudeAccountProfileStoreTests: XCTestCase {
    func testSaveProfileFromConfigDirectoryParsesMetadata() throws {
        let store = makeStore()
        let configDir = makeConfigDirectory(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-dir-a",
                email: "dir-a@example.com",
                accessToken: "access-dir-a"
            )
        )

        let profile = try store.saveProfile(
            slotID: .a,
            displayName: "Dir A",
            note: nil,
            source: .configDir,
            configDir: configDir,
            credentialsJSON: nil,
            currentFingerprint: nil
        )

        XCTAssertEqual(profile.slotID, .a)
        XCTAssertEqual(profile.source, .configDir)
        XCTAssertEqual(profile.accountId, "acc-dir-a")
        XCTAssertEqual(profile.accountEmail, "dir-a@example.com")
        XCTAssertNotNil(profile.credentialFingerprint)
        XCTAssertTrue(profile.credentialsJSON?.contains("access-dir-a") == true)
    }

    func testSaveProfileFromManualCredentialsParsesMetadata() throws {
        let store = makeStore()
        let credentials = sampleCredentialsJSON(
            accountID: "acc-manual-a",
            email: "manual-a@example.com",
            accessToken: "access-manual-a"
        )

        let profile = try store.saveProfile(
            slotID: .a,
            displayName: "Manual A",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: credentials,
            currentFingerprint: nil
        )

        XCTAssertEqual(profile.slotID, .a)
        XCTAssertEqual(profile.source, .manualCredentials)
        XCTAssertEqual(profile.accountId, "acc-manual-a")
        XCTAssertEqual(profile.accountEmail, "manual-a@example.com")
        XCTAssertEqual(
            profile.credentialFingerprint,
            try ClaudeAccountProfileStore.parseCredentialsJSON(credentials).credentialFingerprint
        )
    }

    func testSaveProfileFallsBackToClaudeConfigEmailWhenCredentialsMissingEmail() throws {
        let store = makeStore()
        let configDir = makeConfigDirectory(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-config-fallback",
                email: nil,
                accessToken: "access-config-fallback"
            ),
            claudeJSON: sampleClaudeConfigJSON(email: "config-fallback@example.com")
        )

        let profile = try store.saveProfile(
            slotID: .a,
            displayName: "Config Fallback",
            note: nil,
            source: .configDir,
            configDir: configDir,
            credentialsJSON: nil,
            currentFingerprint: nil
        )

        XCTAssertEqual(profile.accountEmail, "config-fallback@example.com")
    }

    func testManualCredentialsWithConfigDirFallsBackToClaudeConfigEmail() throws {
        let store = makeStore()
        let configDir = makeConfigDirectory(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-manual-config",
                email: nil,
                accessToken: "access-manual-config"
            ),
            claudeJSON: sampleClaudeConfigJSON(email: "manual-config@example.com")
        )
        let manualCredentials = sampleCredentialsJSON(
            accountID: "acc-manual-config",
            email: nil,
            accessToken: "access-manual-config"
        )

        let profile = try store.saveProfile(
            slotID: .a,
            displayName: "Manual Config",
            note: nil,
            source: .manualCredentials,
            configDir: configDir,
            credentialsJSON: manualCredentials,
            currentFingerprint: nil
        )

        XCTAssertEqual(profile.accountEmail, "manual-config@example.com")
    }

    func testManualCredentialsWithoutConfigDirDoesNotFallbackEmail() throws {
        let store = makeStore()
        let manualCredentials = sampleCredentialsJSON(
            accountID: "acc-manual-only",
            email: nil,
            accessToken: "access-manual-only"
        )

        let profile = try store.saveProfile(
            slotID: .a,
            displayName: "Manual Only",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: manualCredentials,
            currentFingerprint: nil
        )

        XCTAssertNil(profile.accountEmail)
    }

    func testNextAvailableSlotIDAdvancesPastImportedProfiles() throws {
        let store = makeStore()
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "A",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-a",
                email: "a@example.com",
                accessToken: "access-a"
            ),
            currentFingerprint: nil
        )
        _ = try store.saveProfile(
            slotID: CodexSlotID(rawValue: "C"),
            displayName: "C",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-c",
                email: "c@example.com",
                accessToken: "access-c"
            ),
            currentFingerprint: nil
        )

        XCTAssertEqual(store.nextAvailableSlotID().rawValue, "B")
    }

    func testFingerprintDedupMovesProfileIntoChosenSlot() throws {
        let store = makeStore()
        let shared = sampleCredentialsJSON(
            accountID: "acc-shared",
            email: "shared@example.com",
            accessToken: "access-shared"
        )

        _ = try store.saveProfile(
            slotID: .a,
            displayName: "A",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: shared,
            currentFingerprint: nil
        )
        _ = try store.saveProfile(
            slotID: .b,
            displayName: "B",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: shared,
            currentFingerprint: nil
        )

        let profiles = store.profiles()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.slotID, .b)
    }

    func testSameEmailDifferentFingerprintDoesNotMerge() throws {
        let store = makeStore()
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "A",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-a",
                email: "shared@example.com",
                accessToken: "access-a"
            ),
            currentFingerprint: nil
        )
        _ = try store.saveProfile(
            slotID: .b,
            displayName: "B",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-b",
                email: "shared@example.com",
                accessToken: "access-b"
            ),
            currentFingerprint: nil
        )

        let profiles = store.profiles()
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(Set(profiles.map(\.slotID.rawValue)), ["A", "B"])
        XCTAssertEqual(Set(profiles.compactMap(\.credentialFingerprint)).count, 2)
    }

    func testCaptureCurrentCredentialsStoresAThenBThenC() {
        let store = makeStore()

        _ = store.captureCurrentCredentialsIfNeeded(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-a",
                email: "a@example.com",
                accessToken: "access-a"
            ),
            defaultConfigDir: nil
        )
        _ = store.captureCurrentCredentialsIfNeeded(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-b",
                email: "b@example.com",
                accessToken: "access-b"
            ),
            defaultConfigDir: nil
        )
        let profiles = store.captureCurrentCredentialsIfNeeded(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-c",
                email: "c@example.com",
                accessToken: "access-c"
            ),
            defaultConfigDir: nil
        )

        XCTAssertEqual(profiles.map(\.slotID.rawValue), ["A", "B", "C"])
        XCTAssertEqual(profiles.filter(\.isCurrentSystemAccount).count, 1)
        XCTAssertEqual(profiles.first(where: \.isCurrentSystemAccount)?.slotID.rawValue, "C")
    }

    func testCaptureCurrentCredentialsSameAccountDifferentAccessTokenDoesNotCreateNewProfile() throws {
        let store = makeStore()
        let configDir = makeConfigDirectory(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-same",
                email: "same@example.com",
                accessToken: "access-token-v1"
            )
        )

        let firstProfiles = store.captureCurrentCredentialsIfNeeded(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-same",
                email: "same@example.com",
                accessToken: "access-token-v1"
            ),
            defaultConfigDir: configDir
        )
        XCTAssertEqual(firstProfiles.count, 1)

        let secondJSON = sampleCredentialsJSON(
            accountID: "acc-same",
            email: "same@example.com",
            accessToken: "access-token-v2"
        )
        let secondProfiles = store.captureCurrentCredentialsIfNeeded(
            credentialsJSON: secondJSON,
            defaultConfigDir: configDir
        )

        XCTAssertEqual(secondProfiles.count, 1)
        XCTAssertEqual(secondProfiles.first?.slotID, firstProfiles.first?.slotID)
        XCTAssertEqual(secondProfiles.first?.accountId, "acc-same")
        XCTAssertEqual(
            secondProfiles.first?.credentialFingerprint,
            try ClaudeAccountProfileStore.parseCredentialsJSON(secondJSON).credentialFingerprint
        )
    }

    func testCompactAutoCapturedProfilesMergesSameAccountAndReturnsRemovedSlots() throws {
        let store = makeStore()
        let credentialsA = sampleCredentialsJSON(
            accountID: "acc-compact",
            email: "compact@example.com",
            accessToken: "compact-token-a"
        )
        let credentialsB = sampleCredentialsJSON(
            accountID: "acc-compact",
            email: "compact@example.com",
            accessToken: "compact-token-b"
        )
        let configDirA = makeConfigDirectory(credentialsJSON: credentialsA)
        let configDirB = makeConfigDirectory(credentialsJSON: credentialsB)
        let fingerprintB = try ClaudeAccountProfileStore.parseCredentialsJSON(credentialsB).credentialFingerprint

        _ = try store.saveProfile(
            slotID: .a,
            displayName: "A",
            note: nil,
            source: .configDir,
            configDir: configDirA,
            credentialsJSON: nil,
            currentFingerprint: nil
        )
        _ = try store.saveProfile(
            slotID: .b,
            displayName: "B",
            note: nil,
            source: .configDir,
            configDir: configDirB,
            credentialsJSON: nil,
            currentFingerprint: nil
        )

        let result = store.compactAutoCapturedProfiles(
            defaultConfigDir: configDirA,
            currentFingerprint: fingerprintB
        )

        XCTAssertTrue(result.didCompact)
        XCTAssertEqual(result.profiles.count, 1)
        XCTAssertEqual(result.profiles.first?.slotID, .b)
        XCTAssertEqual(result.profiles.first?.accountId, "acc-compact")
        XCTAssertEqual(result.removedSlotIDs, [.a])
        XCTAssertTrue(result.profiles.first?.isCurrentSystemAccount == true)
    }

    func testRemovedCurrentFingerprintIsNotAutoCapturedAgainImmediately() throws {
        let store = makeStore()
        let credentialsJSON = sampleCredentialsJSON(
            accountID: "acc-current",
            email: "current@example.com",
            accessToken: "access-current"
        )
        let fingerprint = try ClaudeAccountProfileStore.parseCredentialsJSON(credentialsJSON).credentialFingerprint

        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Current",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: credentialsJSON,
            currentFingerprint: fingerprint
        )
        _ = store.removeProfile(slotID: .a)
        let profiles = store.captureCurrentCredentialsIfNeeded(
            credentialsJSON: credentialsJSON,
            defaultConfigDir: nil
        )

        XCTAssertTrue(profiles.isEmpty)
    }

    func testProfilesBackfillEmailFromClaudeConfigForLegacyStoredProfile() throws {
        let storeFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-profile-legacy-\(UUID().uuidString).json")
        let configDir = makeConfigDirectory(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-legacy",
                email: nil,
                accessToken: "legacy-access-token"
            ),
            claudeJSON: sampleClaudeConfigJSON(email: "legacy-backfilled@example.com")
        )
        let credentialsJSON = sampleCredentialsJSON(
            accountID: "acc-legacy",
            email: nil,
            accessToken: "legacy-access-token"
        )
        let fingerprint = try ClaudeAccountProfileStore.parseCredentialsJSON(credentialsJSON).credentialFingerprint
        let importedAt = Date(timeIntervalSince1970: 1_745_280_000)
        let importedAtISO = ISO8601DateFormatter().string(from: importedAt)
        let legacyRoot: [String: Any] = [
            "profiles": [
                [
                    "slotID": "A",
                    "displayName": "Claude A",
                    "note": NSNull(),
                    "source": "configDir",
                    "configDir": configDir,
                    "credentialsJSON": credentialsJSON,
                    "accountId": "acc-legacy",
                    "accountEmail": NSNull(),
                    "credentialFingerprint": fingerprint,
                    "lastImportedAt": importedAtISO,
                    "isCurrentSystemAccount": false
                ]
            ]
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: legacyRoot, options: [.prettyPrinted, .sortedKeys])
        try legacyData.write(to: storeFile, options: .atomic)

        let store = ClaudeAccountProfileStore(fileURL: storeFile)
        let profiles = store.profiles()

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.slotID, .a)
        XCTAssertEqual(profiles.first?.accountEmail, "legacy-backfilled@example.com")
        XCTAssertEqual(profiles.first?.credentialFingerprint, fingerprint)
    }

    private func makeStore() -> ClaudeAccountProfileStore {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-profile-tests-\(UUID().uuidString).json")
        return ClaudeAccountProfileStore(fileURL: path)
    }

    private func makeConfigDirectory(credentialsJSON: String, claudeJSON: String? = nil) -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-profile-dir-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let credentialsURL = directory.appendingPathComponent(".credentials.json")
        try? credentialsJSON.data(using: .utf8)?.write(to: credentialsURL, options: .atomic)
        if let claudeJSON {
            let claudeConfigURL = directory.appendingPathComponent("claude.json")
            try? claudeJSON.data(using: .utf8)?.write(to: claudeConfigURL, options: .atomic)
        }
        return directory.path
    }

    private func sampleCredentialsJSON(
        accountID: String?,
        email: String?,
        accessToken: String,
        refreshToken: String = "refresh-token",
        expiresAtMs: Double = 4_102_444_800_000
    ) -> String {
        var root: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": accessToken,
                "refreshToken": refreshToken,
                "expiresAt": expiresAtMs,
                "subscriptionType": "pro",
                "scopes": ["user:profile"]
            ]
        ]
        if let accountID {
            root["accountId"] = accountID
        }
        if let email {
            root["email"] = email
        }
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private func sampleClaudeConfigJSON(email: String) -> String {
        let root: [String: Any] = [
            "user": [
                "email": email
            ],
            "ui": [
                "theme": "dark"
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
