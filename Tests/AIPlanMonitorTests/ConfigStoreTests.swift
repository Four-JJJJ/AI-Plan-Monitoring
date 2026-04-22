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
}
