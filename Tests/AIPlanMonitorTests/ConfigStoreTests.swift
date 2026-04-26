import XCTest
@testable import AIPlanMonitor

final class ConfigStoreTests: XCTestCase {
    func testSaveWritesPrimaryAndBackupAndLoadReturnsPersistedConfig() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)

        var config = AppConfig.default
        config.language = .en
        if let codexIndex = config.providers.firstIndex(where: { $0.id == "codex-official" }) {
            config.providers[codexIndex].enabled = true
        }

        try store.save(config)
        let directory = root.appendingPathComponent("AIPlanMonitor", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.backup.json").path))

        let loaded = try store.load()
        XCTAssertEqual(loaded.language, .en)
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "codex-official" && $0.enabled }))
    }

    func testLoadRecoversEnabledOfficialProvidersFromPersistedProfilesWhenConfigMissing() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)

        let codexProfilesURL = appSupportDirectory(in: root).appendingPathComponent("codex_profiles.json")
        let codexProfileStore = CodexAccountProfileStore(fileURL: codexProfilesURL)
        _ = try codexProfileStore.saveProfile(
            slotID: .a,
            displayName: "Codex A",
            note: nil,
            authJSON: #"{"tokens":{"access_token":"codex-test-token"}}"#,
            currentFingerprint: nil
        )

        let claudeProfilesURL = appSupportDirectory(in: root).appendingPathComponent("claude_profiles.json")
        let claudeProfileStore = ClaudeAccountProfileStore(fileURL: claudeProfilesURL)
        _ = try claudeProfileStore.saveProfile(
            slotID: .a,
            displayName: "Claude A",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: #"{"accessToken":"claude-test-token","email":"test@example.com"}"#,
            currentFingerprint: nil
        )

        let loaded = try store.load()
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "codex-official" && $0.enabled }))
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "claude-official" && $0.enabled }))
        XCTAssertEqual(loaded.statusBarProviderID, "codex-official")

        let configURL = appSupportDirectory(in: root).appendingPathComponent("config.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testLoadRecoversFromBackupWhenPrimaryConfigCorrupted() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)

        var config = AppConfig.default
        config.language = .en
        try store.save(config)

        let directory = root.appendingPathComponent("AIPlanMonitor", isDirectory: true)
        let primaryURL = directory.appendingPathComponent("config.json")
        try Data("not-json".utf8).write(to: primaryURL, options: .atomic)

        let loaded = try store.load()
        XCTAssertEqual(loaded.language, .en)

        let restoredData = try Data(contentsOf: primaryURL)
        XCTAssertNoThrow(try JSONDecoder().decode(AppConfig.self, from: restoredData))
    }

    func testLoadRecoversEnabledOfficialProvidersFromPersistedSlotsWhenPrimaryAndBackupCorrupted() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let directory = appSupportDirectory(in: root)

        let codexSlotStore = CodexAccountSlotStore(
            staleInterval: .greatestFiniteMagnitude,
            fileURL: directory.appendingPathComponent("codex_slots.json")
        )
        _ = codexSlotStore.upsertActive(
            snapshot: makeSnapshot(
                source: "codex-official",
                accountLabel: "codex@example.com",
                rawMeta: [
                    "codex.accountKey": "tenant:account:codex|principal:email:codex@example.com",
                    "codex.slotID": "A"
                ]
            ),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let claudeSlotStore = ClaudeAccountSlotStore(
            staleInterval: .greatestFiniteMagnitude,
            fileURL: directory.appendingPathComponent("claude_slots.json")
        )
        _ = claudeSlotStore.upsertActive(
            snapshot: makeSnapshot(
                source: "claude-official",
                accountLabel: "claude@example.com",
                rawMeta: [
                    "claude.accountKey": "claude:claude@example.com",
                    "claude.slotID": "A"
                ]
            ),
            now: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let primaryURL = directory.appendingPathComponent("config.json")
        let backupURL = directory.appendingPathComponent("config.backup.json")
        try Data("not-json".utf8).write(to: primaryURL, options: .atomic)
        try Data("still-not-json".utf8).write(to: backupURL, options: .atomic)

        let loaded = try store.load()
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "codex-official" && $0.enabled }))
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "claude-official" && $0.enabled }))

        let restoredData = try Data(contentsOf: primaryURL)
        XCTAssertNoThrow(try JSONDecoder().decode(AppConfig.self, from: restoredData))
    }

    func testResetRemovesPrimaryAndBackup() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        try store.save(.default)

        let directory = root.appendingPathComponent("AIPlanMonitor", isDirectory: true)
        let primaryURL = directory.appendingPathComponent("config.json")
        let backupURL = directory.appendingPathComponent("config.backup.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: primaryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))

        try store.reset()

        XCTAssertFalse(FileManager.default.fileExists(atPath: primaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("config-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func appSupportDirectory(in root: URL) -> URL {
        root.appendingPathComponent("AIPlanMonitor", isDirectory: true)
    }

    private func makeSnapshot(
        source: String,
        accountLabel: String,
        rawMeta: [String: String]
    ) -> UsageSnapshot {
        UsageSnapshot(
            source: source,
            status: .ok,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            note: "Persisted snapshot",
            sourceLabel: "Test",
            accountLabel: accountLabel,
            extras: [:],
            rawMeta: rawMeta
        )
    }
}
