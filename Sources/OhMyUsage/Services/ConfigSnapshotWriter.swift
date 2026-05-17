import Foundation

final class ConfigSnapshotWriter {
    private let paths: ConfigStorePaths
    private let fileManager: FileManager
    private let log: (String) -> Void

    init(
        paths: ConfigStorePaths,
        fileManager: FileManager,
        log: @escaping (String) -> Void
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.log = log
    }

    func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: paths.directoryURL.path) {
            try fileManager.createDirectory(at: paths.directoryURL, withIntermediateDirectories: true)
        }
    }

    func save(
        _ config: AppConfig,
        updateLastKnownGood: Bool,
        clearPreservedFallbackCandidate: Bool
    ) throws {
        try ensureDirectoryExists()
        let data = try encodedConfigData(config)
        try writeData(data, to: paths.fileURL)
        try writeData(data, to: paths.backupFileURL)
        try writeData(data, to: paths.recoveryFileURL)
        if updateLastKnownGood {
            try writeLastKnownGoodIfEligible(data, overwriteExisting: true)
        }
        if clearPreservedFallbackCandidate {
            try removePreservedFallbackCandidateIfPresent()
        }
    }

    func syncShadowCopiesIfNeeded(primaryData: Data) throws {
        if !fileManager.fileExists(atPath: paths.backupFileURL.path) {
            try writeData(primaryData, to: paths.backupFileURL)
        }
        if !fileManager.fileExists(atPath: paths.recoveryFileURL.path) {
            try writeData(primaryData, to: paths.recoveryFileURL)
        }
        try writeLastKnownGoodIfEligible(primaryData, overwriteExisting: false)
    }

    func preserveFallbackCandidateIfNeeded(_ data: Data?) throws {
        guard let data, !data.isEmpty else { return }
        try writeData(data, to: paths.preservedFallbackCandidateFileURL)
    }

    private func encodedConfigData(_ config: AppConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }

    private func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    private func writeLastKnownGoodIfEligible(_ data: Data, overwriteExisting: Bool) throws {
        if !overwriteExisting, fileManager.fileExists(atPath: paths.lastKnownGoodFileURL.path) {
            return
        }
        let decoded = try AppConfig.decodeWithDiagnostics(from: data)
        guard !decoded.diagnostics.hadLossyProviderDecoding else {
            log(
                "Skipped updating last-known-good snapshot because provider decoding dropped \(decoded.diagnostics.droppedProviderEntryCount) entries"
            )
            return
        }
        try writeData(data, to: paths.lastKnownGoodFileURL)
    }

    private func removePreservedFallbackCandidateIfPresent() throws {
        if fileManager.fileExists(atPath: paths.preservedFallbackCandidateFileURL.path) {
            try fileManager.removeItem(at: paths.preservedFallbackCandidateFileURL)
        }
    }
}
