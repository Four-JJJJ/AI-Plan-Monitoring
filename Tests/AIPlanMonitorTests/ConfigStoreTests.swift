import XCTest
@testable import AIPlanMonitor

final class ConfigStoreTests: XCTestCase {
    func testSaveWritesPrimaryBackupAndRecoveryAndLoadReturnsPersistedConfig() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)

        var config = AppConfig.default
        config.language = .en
        config.claudeStatusBarDisplaySlotID = .b
        if let codexIndex = config.providers.firstIndex(where: { $0.id == "codex-official" }) {
            config.providers[codexIndex].enabled = true
        }

        try store.save(config)
        let directory = root.appendingPathComponent("AIPlanMonitor", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.backup.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.recovery.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.last-known-good.json").path))

        let loaded = try store.load()
        XCTAssertEqual(loaded.language, .en)
        XCTAssertEqual(loaded.claudeStatusBarDisplaySlotID, .b)
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "codex-official" && $0.enabled }))
    }

    func testLoadCreatesDefaultConfigWhenNoHistoryExists() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)

        let loaded = try store.load()
        let directory = appSupportDirectory(in: root)

        XCTAssertEqual(loaded, AppConfig.default)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.backup.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.recovery.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.last-known-good.json").path))
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

    func testLoadRecoversFromRecoverySnapshotWhenPrimaryAndBackupCorrupted() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)

        var config = AppConfig.default
        config.statusBarMultiUsageEnabled = true
        config.statusBarProviderID = "codex-official"
        config.statusBarMultiProviderIDs = ["codex-official", "claude-official"]
        config.claudeStatusBarDisplaySlotID = .b
        config.statusBarAppearanceMode = .dark
        config.statusBarDisplayStyle = .barNamePercent
        if let codexIndex = config.providers.firstIndex(where: { $0.id == "codex-official" }) {
            config.providers[codexIndex].enabled = true
        }
        if let claudeIndex = config.providers.firstIndex(where: { $0.id == "claude-official" }) {
            config.providers[claudeIndex].enabled = true
        }
        try store.save(config)

        let directory = root.appendingPathComponent("AIPlanMonitor", isDirectory: true)
        let primaryURL = directory.appendingPathComponent("config.json")
        let backupURL = directory.appendingPathComponent("config.backup.json")
        let lastKnownGoodURL = directory.appendingPathComponent("config.last-known-good.json")
        try Data("not-json".utf8).write(to: primaryURL, options: .atomic)
        try Data("still-not-json".utf8).write(to: backupURL, options: .atomic)

        let loaded = try store.load()
        XCTAssertEqual(loaded.statusBarProviderID, "codex-official")
        XCTAssertEqual(loaded.claudeStatusBarDisplaySlotID, .b)
        XCTAssertTrue(loaded.statusBarMultiUsageEnabled)
        XCTAssertEqual(loaded.statusBarMultiProviderIDs, ["codex-official", "claude-official"])
        XCTAssertEqual(loaded.statusBarAppearanceMode, .dark)
        XCTAssertEqual(loaded.statusBarDisplayStyle, .barNamePercent)

        let restoredPrimary = try Data(contentsOf: primaryURL)
        let restoredBackup = try Data(contentsOf: backupURL)
        XCTAssertNoThrow(try JSONDecoder().decode(AppConfig.self, from: restoredPrimary))
        XCTAssertNoThrow(try JSONDecoder().decode(AppConfig.self, from: restoredBackup))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lastKnownGoodURL.path))
    }

    func testLoadRecoversFromLastKnownGoodWhenPrimaryAndShadowsMissing() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let config = makeConfigWithRelayAndStatusBarState()
        try store.save(config)

        let directory = appSupportDirectory(in: root)
        let primaryURL = directory.appendingPathComponent("config.json")
        let backupURL = directory.appendingPathComponent("config.backup.json")
        let recoveryURL = directory.appendingPathComponent("config.recovery.json")
        let lastKnownGoodURL = directory.appendingPathComponent("config.last-known-good.json")

        try FileManager.default.removeItem(at: primaryURL)
        try FileManager.default.removeItem(at: backupURL)
        try FileManager.default.removeItem(at: recoveryURL)

        let loaded = try store.load()

        XCTAssertEqual(loaded.statusBarProviderID, "open-custom-relay-persisted")
        XCTAssertTrue(loaded.statusBarMultiUsageEnabled)
        XCTAssertEqual(loaded.statusBarMultiProviderIDs, ["codex-official", "open-custom-relay-persisted"])
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "open-custom-relay-persisted" && $0.enabled }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: primaryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lastKnownGoodURL.path))
    }

    func testLoadPrefersLossyCurrentConfigBeforeRestoringLastKnownGoodSnapshot() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let config = makeConfigWithRelayAndStatusBarState()
        try store.save(config)

        let directory = appSupportDirectory(in: root)
        let lossyData = Data(makeLossyConfigJSON().utf8)
        try lossyData.write(to: directory.appendingPathComponent("config.json"), options: .atomic)
        try lossyData.write(to: directory.appendingPathComponent("config.backup.json"), options: .atomic)
        try lossyData.write(to: directory.appendingPathComponent("config.recovery.json"), options: .atomic)

        let loaded = try store.load()
        let restoredData = try Data(contentsOf: directory.appendingPathComponent("config.json"))
        let restored = try AppConfig.decodeWithDiagnostics(from: restoredData)
        let preservedURL = directory.appendingPathComponent("config.preserved-fallback-candidate.json")

        XCTAssertTrue(restored.diagnostics.hadLossyProviderDecoding)
        XCTAssertEqual(loaded.statusBarProviderID, "codex-official")
        XCTAssertTrue(loaded.statusBarMultiUsageEnabled)
        XCTAssertEqual(loaded.statusBarMultiProviderIDs, ["codex-official"])
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "codex-official" && $0.enabled }))
        XCTAssertFalse(loaded.providers.contains(where: { $0.id == "open-custom-relay-persisted" && $0.enabled }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preservedURL.path))
        XCTAssertEqual(try Data(contentsOf: preservedURL), lossyData)
    }

    func testBootstrapSaveDoesNotOverwriteLastKnownGoodSnapshot() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let fullConfig = makeConfigWithRelayAndStatusBarState()
        try store.save(fullConfig)

        var minimal = AppConfig.default
        if let codexIndex = minimal.providers.firstIndex(where: { $0.id == "codex-official" }) {
            minimal.providers[codexIndex].enabled = true
        }
        minimal.statusBarProviderID = "codex-official"
        minimal.statusBarMultiUsageEnabled = false
        minimal.statusBarMultiProviderIDs = ["codex-official"]
        minimal.launchAtLoginEnabled = true

        try store.saveDuringBootstrap(minimal)

        let directory = appSupportDirectory(in: root)
        let primary = try AppConfig.decodeWithDiagnostics(
            from: Data(contentsOf: directory.appendingPathComponent("config.json"))
        ).config
        let lastKnownGood = try AppConfig.decodeWithDiagnostics(
            from: Data(contentsOf: directory.appendingPathComponent("config.last-known-good.json"))
        ).config

        XCTAssertEqual(primary.statusBarProviderID, "codex-official")
        XCTAssertFalse(primary.statusBarMultiUsageEnabled)
        XCTAssertEqual(primary.statusBarMultiProviderIDs, ["codex-official"])
        XCTAssertEqual(lastKnownGood.statusBarProviderID, "open-custom-relay-persisted")
        XCTAssertTrue(lastKnownGood.statusBarMultiUsageEnabled)
        XCTAssertEqual(lastKnownGood.statusBarMultiProviderIDs, ["codex-official", "open-custom-relay-persisted"])
        XCTAssertTrue(lastKnownGood.providers.contains(where: { $0.id == "open-custom-relay-persisted" && $0.enabled }))
    }

    func testLoadPersistsPreservedFallbackCandidateWhenLossyConfigLoadsInPlace() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let directory = appSupportDirectory(in: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let lossyData = Data(makeLossyConfigJSON().utf8)
        try lossyData.write(to: directory.appendingPathComponent("config.json"), options: .atomic)
        try lossyData.write(to: directory.appendingPathComponent("config.backup.json"), options: .atomic)
        try lossyData.write(to: directory.appendingPathComponent("config.recovery.json"), options: .atomic)

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

        let loaded = try store.load()
        let preservedURL = directory.appendingPathComponent("config.preserved-fallback-candidate.json")

        XCTAssertEqual(loaded.statusBarProviderID, "codex-official")
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "codex-official" && $0.enabled }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preservedURL.path))
        XCTAssertEqual(try Data(contentsOf: preservedURL), lossyData)
    }

    func testLoadPrefersPreservedFallbackCandidateBeforeDerivedPrimaryConfig() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let fullConfig = makeConfigWithRelayAndStatusBarState()
        let directory = appSupportDirectory(in: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var minimal = AppConfig.default
        if let codexIndex = minimal.providers.firstIndex(where: { $0.id == "codex-official" }) {
            minimal.providers[codexIndex].enabled = true
        }
        minimal.statusBarProviderID = "codex-official"
        minimal.statusBarMultiProviderIDs = ["codex-official"]
        let minimalData = try JSONEncoder.prettySorted.encode(minimal)
        try minimalData.write(to: directory.appendingPathComponent("config.json"), options: .atomic)
        try minimalData.write(to: directory.appendingPathComponent("config.backup.json"), options: .atomic)
        try minimalData.write(to: directory.appendingPathComponent("config.recovery.json"), options: .atomic)

        let fullData = try JSONEncoder.prettySorted.encode(fullConfig)
        try fullData.write(to: directory.appendingPathComponent("config.preserved-fallback-candidate.json"), options: .atomic)

        let loaded = try store.load()
        let rewrittenPrimary = try AppConfig.decodeWithDiagnostics(
            from: Data(contentsOf: directory.appendingPathComponent("config.json"))
        ).config

        XCTAssertEqual(loaded.statusBarProviderID, "open-custom-relay-persisted")
        XCTAssertTrue(loaded.statusBarMultiUsageEnabled)
        XCTAssertEqual(loaded.statusBarMultiProviderIDs, ["codex-official", "open-custom-relay-persisted"])
        XCTAssertTrue(rewrittenPrimary.providers.contains(where: { $0.id == "open-custom-relay-persisted" && $0.enabled }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.preserved-fallback-candidate.json").path))
    }

    func testLoadRecoversFromLastKnownGoodWhenPrimaryBackupAndRecoveryCorrupted() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let config = makeConfigWithRelayAndStatusBarState()
        try store.save(config)

        let directory = appSupportDirectory(in: root)
        let primaryURL = directory.appendingPathComponent("config.json")
        let backupURL = directory.appendingPathComponent("config.backup.json")
        let recoveryURL = directory.appendingPathComponent("config.recovery.json")

        try Data("not-json".utf8).write(to: primaryURL, options: .atomic)
        try Data("still-not-json".utf8).write(to: backupURL, options: .atomic)
        try Data("definitely-not-json".utf8).write(to: recoveryURL, options: .atomic)

        let loaded = try store.load()

        XCTAssertEqual(loaded.statusBarProviderID, "open-custom-relay-persisted")
        XCTAssertEqual(loaded.statusBarMultiProviderIDs, ["codex-official", "open-custom-relay-persisted"])
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "open-custom-relay-persisted" && $0.enabled }))
        XCTAssertNoThrow(try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: primaryURL)))
        XCTAssertNoThrow(try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: backupURL)))
        XCTAssertNoThrow(try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: recoveryURL)))
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
        let recoveryURL = directory.appendingPathComponent("config.recovery.json")
        let lastKnownGoodURL = directory.appendingPathComponent("config.last-known-good.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: primaryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lastKnownGoodURL.path))

        try store.reset()

        XCTAssertFalse(FileManager.default.fileExists(atPath: primaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: lastKnownGoodURL.path))
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

    private func makeConfigWithRelayAndStatusBarState() -> AppConfig {
        var providers = AppConfig.default.providers
        if let codexIndex = providers.firstIndex(where: { $0.id == "codex-official" }) {
            providers[codexIndex].enabled = true
        }

        var relay = ProviderDescriptor.makeOpenRelay(
            name: "Persisted Relay",
            baseURL: "https://relay.persisted.example"
        )
        relay.id = "open-custom-relay-persisted"
        relay.enabled = true
        providers.insert(relay, at: 1)

        return AppConfig(
            language: .en,
            launchAtLoginEnabled: true,
            showOfficialAccountEmailInMenuBar: true,
            claudeStatusBarDisplaySlotID: .b,
            statusBarProviderID: relay.id,
            statusBarMultiUsageEnabled: true,
            statusBarMultiProviderIDs: ["codex-official", relay.id],
            statusBarAppearanceMode: .dark,
            statusBarDisplayStyle: .barNamePercent,
            providers: providers
        )
    }

    private func makeLossyConfigJSON() -> String {
        #"""
        {
          "language":"en",
          "launchAtLoginEnabled":true,
          "statusBarProviderID":"codex-official",
          "statusBarMultiUsageEnabled":true,
          "statusBarMultiProviderIDs":["codex-official","open-custom-relay-persisted"],
          "providers":[
            {
              "id":"legacy-opencode-go",
              "name":"Legacy OpenCode Go",
              "family":"official",
              "type":"openCodeGo",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"bearer"}
            },
            {
              "id":"codex-official",
              "name":"Official Codex",
              "family":"official",
              "type":"codex",
              "enabled":true,
              "pollIntervalSec":120,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"localCodex"},
              "baseURL":"https://chatgpt.com"
            }
          ]
        }
        """#
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

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
