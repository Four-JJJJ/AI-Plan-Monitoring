import Foundation

final class ThirdPartyBalanceBaselineStore {
    private struct Payload: Codable {
        var entries: [String: ThirdPartyBalanceBaselineTracker.Entry]
    }

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directory = appSupport.appendingPathComponent("AIPlanMonitor", isDirectory: true)
            self.fileURL = directory.appendingPathComponent("third_party_balance_baselines.json")
        }
    }

    func load() -> [String: ThirdPartyBalanceBaselineTracker.Entry] {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return [:]
        }
        return payload.entries
    }

    func save(_ entries: [String: ThirdPartyBalanceBaselineTracker.Entry]) {
        let directory = fileURL.deletingLastPathComponent()
        do {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            if entries.isEmpty {
                if fileManager.fileExists(atPath: fileURL.path) {
                    try fileManager.removeItem(at: fileURL)
                }
                return
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Payload(entries: entries))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }

    func reset() {
        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
