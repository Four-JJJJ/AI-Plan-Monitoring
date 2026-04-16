import Foundation

final class ConfigStore {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("AIPlanMonitor", isDirectory: true)
        self.fileURL = directory.appendingPathComponent("config.json")
    }

    func load() throws -> AppConfig {
        let manager = FileManager.default
        let dirURL = fileURL.deletingLastPathComponent()

        if !manager.fileExists(atPath: dirURL.path) {
            try manager.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }

        if !manager.fileExists(atPath: fileURL.path) {
            try save(AppConfig.default)
            return .default
        }

        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        let migrated = decoded.migratedWithSiteDefaults()
        if migrated != decoded {
            try save(migrated)
        }
        return migrated
    }

    func save(_ config: AppConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }

    func reset() throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }
}
