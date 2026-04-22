import Foundation

final class ConfigStore {
    private let fileURL: URL
    private let backupFileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        let rootDirectory: URL
        if let baseDirectoryURL {
            rootDirectory = baseDirectoryURL
        } else {
            rootDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        }
        let directory = rootDirectory.appendingPathComponent("AIPlanMonitor", isDirectory: true)
        self.fileURL = directory.appendingPathComponent("config.json")
        self.backupFileURL = directory.appendingPathComponent("config.backup.json")
    }

    func load() throws -> AppConfig {
        try ensureDirectoryExists()

        if !fileManager.fileExists(atPath: fileURL.path) {
            if let recovered = try loadFromBackupAndRestoreIfNeeded() {
                return recovered
            }
            try save(AppConfig.default)
            return .default
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
            let migrated = decoded.migratedWithSiteDefaults()
            if migrated != decoded {
                try save(migrated)
                return migrated
            }

            // Keep backup in sync even when the main file is loaded unchanged.
            if !fileManager.fileExists(atPath: backupFileURL.path) {
                try writeData(data, to: backupFileURL)
            }
            return migrated
        } catch {
            if let recovered = try loadFromBackupAndRestoreIfNeeded() {
                return recovered
            }
            throw error
        }
    }

    func save(_ config: AppConfig) throws {
        try ensureDirectoryExists()
        let data = try encodedConfigData(config)
        try writeData(data, to: fileURL)
        try writeData(data, to: backupFileURL)
    }

    func reset() throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        if fileManager.fileExists(atPath: backupFileURL.path) {
            try fileManager.removeItem(at: backupFileURL)
        }
    }

    private func ensureDirectoryExists() throws {
        let dirURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dirURL.path) {
            try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
    }

    private func encodedConfigData(_ config: AppConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }

    private func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    private func loadFromBackupAndRestoreIfNeeded() throws -> AppConfig? {
        guard fileManager.fileExists(atPath: backupFileURL.path) else {
            return nil
        }
        let backupData = try Data(contentsOf: backupFileURL)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: backupData)
        let migrated = decoded.migratedWithSiteDefaults()
        if migrated != decoded {
            try save(migrated)
            return migrated
        }
        // Restore primary from backup so later launches don't keep failing on a corrupted primary file.
        try writeData(backupData, to: fileURL)
        return migrated
    }
}
