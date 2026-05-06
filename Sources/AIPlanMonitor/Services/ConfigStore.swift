import Foundation

final class ConfigStore {
    private enum PersistedConfigSource: String {
        case primary = "primary"
        case backup = "backup"
        case recovery = "recovery"
        case lastKnownGood = "last-known-good"
        case preservedFallbackCandidate = "preserved-fallback-candidate"
    }

    private enum StoredConfigLoadResult {
        case missing
        case invalid(Data, Error)
        case lossy(StoredConfigSnapshot, AppConfigDecodeDiagnostics)
        case usable(StoredConfigSnapshot)
    }

    private struct StoredConfigSnapshot {
        let source: PersistedConfigSource
        let rawData: Data
        let config: AppConfig
        let wasMigrated: Bool
    }

    private enum PersistedOfficialState: CaseIterable {
        case codex
        case claude

        var providerID: String {
            switch self {
            case .codex:
                return "codex-official"
            case .claude:
                return "claude-official"
            }
        }
    }

    private let fileURL: URL
    private let backupFileURL: URL
    private let recoveryFileURL: URL
    private let lastKnownGoodFileURL: URL
    private let preservedFallbackCandidateFileURL: URL
    private let fileManager: FileManager
    private(set) var lastLoadWasLossy = false

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
        self.recoveryFileURL = directory.appendingPathComponent("config.recovery.json")
        self.lastKnownGoodFileURL = directory.appendingPathComponent("config.last-known-good.json")
        self.preservedFallbackCandidateFileURL = directory.appendingPathComponent("config.preserved-fallback-candidate.json")
    }

    func load() throws -> AppConfig {
        try ensureDirectoryExists()
        lastLoadWasLossy = false
        var sawPersistedConfigSource = false
        var preservedFallbackData: Data?
        var lossySnapshot: (snapshot: StoredConfigSnapshot, diagnostics: AppConfigDecodeDiagnostics)?

        if !fileManager.fileExists(atPath: preservedFallbackCandidateFileURL.path) {
            let currentSources: [(PersistedConfigSource, URL)] = [
                (.primary, fileURL),
                (.backup, backupFileURL),
                (.recovery, recoveryFileURL)
            ]

            for (source, url) in currentSources {
                let result = loadStoredConfig(at: url, source: source)
                switch result {
                case .missing:
                    continue
                case .invalid(let data, let error):
                    sawPersistedConfigSource = true
                    if preservedFallbackData == nil {
                        preservedFallbackData = data
                    }
                    log("Ignoring \(source.rawValue) config because it could not be decoded: \(error.localizedDescription)")
                case .lossy(let snapshot, let diagnostics):
                    sawPersistedConfigSource = true
                    if preservedFallbackData == nil {
                        preservedFallbackData = snapshot.rawData
                    }
                    if lossySnapshot == nil {
                        lossySnapshot = (snapshot, diagnostics)
                    }
                    log(
                        "Found lossy \(source.rawValue) config; keeping it as a fallback because provider decoding dropped \(diagnostics.droppedProviderEntryCount) entries"
                    )
                case .usable(let snapshot):
                    return try acceptLoadedSnapshot(snapshot)
                }
            }

            if let lossySnapshot {
                return try acceptLossySnapshot(lossySnapshot.snapshot, diagnostics: lossySnapshot.diagnostics)
            }
        }

        let loadOrder = loadOrder()

        for (source, url) in loadOrder {
            let result = loadStoredConfig(at: url, source: source)
            switch result {
            case .missing:
                continue
            case .invalid(let data, let error):
                sawPersistedConfigSource = true
                if preservedFallbackData == nil, source != .preservedFallbackCandidate {
                    preservedFallbackData = data
                }
                log("Ignoring \(source.rawValue) config because it could not be decoded: \(error.localizedDescription)")
            case .lossy(let snapshot, let diagnostics):
                sawPersistedConfigSource = true
                if preservedFallbackData == nil, source != .preservedFallbackCandidate {
                    preservedFallbackData = snapshot.rawData
                }
                log(
                    "Ignoring \(source.rawValue) config because provider decoding dropped \(diagnostics.droppedProviderEntryCount) entries"
                )
            case .usable(let snapshot):
                return try acceptLoadedSnapshot(snapshot)
            }
        }

        if let recovered = try recoverFromPersistedOfficialStateAndRestoreIfNeeded() {
            try preserveFallbackCandidateIfNeeded(preservedFallbackData)
            log("Recovered official monitoring state from persisted profiles/slots")
            return recovered
        }

        let defaultConfig = AppConfig.default
        try preserveFallbackCandidateIfNeeded(preservedFallbackData)
        try save(defaultConfig)
        if sawPersistedConfigSource {
            log("Fell back to default config after all persisted config sources were invalid or lossy")
        } else {
            log("No persisted config found; wrote default config")
        }
        return defaultConfig
    }

    func save(_ config: AppConfig) throws {
        try save(config, updateLastKnownGood: true, clearPreservedFallbackCandidate: true)
    }

    func saveDuringBootstrap(_ config: AppConfig) throws {
        try save(config, updateLastKnownGood: false, clearPreservedFallbackCandidate: false)
    }

    private func save(
        _ config: AppConfig,
        updateLastKnownGood: Bool,
        clearPreservedFallbackCandidate: Bool
    ) throws {
        try ensureDirectoryExists()
        let data = try encodedConfigData(config)
        try writeData(data, to: fileURL)
        try writeData(data, to: backupFileURL)
        try writeData(data, to: recoveryFileURL)
        if updateLastKnownGood {
            try writeLastKnownGoodIfEligible(data, overwriteExisting: true)
        }
        if clearPreservedFallbackCandidate {
            try removePreservedFallbackCandidateIfPresent()
        }
    }

    func reset() throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        if fileManager.fileExists(atPath: backupFileURL.path) {
            try fileManager.removeItem(at: backupFileURL)
        }
        if fileManager.fileExists(atPath: recoveryFileURL.path) {
            try fileManager.removeItem(at: recoveryFileURL)
        }
        if fileManager.fileExists(atPath: lastKnownGoodFileURL.path) {
            try fileManager.removeItem(at: lastKnownGoodFileURL)
        }
        if fileManager.fileExists(atPath: preservedFallbackCandidateFileURL.path) {
            try fileManager.removeItem(at: preservedFallbackCandidateFileURL)
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

    private func loadStoredConfig(at url: URL, source: PersistedConfigSource) -> StoredConfigLoadResult {
        guard fileManager.fileExists(atPath: url.path) else {
            return .missing
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try AppConfig.decodeWithDiagnostics(from: data)
            let migrated = decoded.config.migratedWithSiteDefaults()
            if decoded.diagnostics.hadLossyProviderDecoding {
                return .lossy(
                    StoredConfigSnapshot(
                        source: source,
                        rawData: data,
                        config: migrated,
                        wasMigrated: migrated != decoded.config
                    ),
                    decoded.diagnostics
                )
            }
            return .usable(
                StoredConfigSnapshot(
                    source: source,
                    rawData: data,
                    config: migrated,
                    wasMigrated: migrated != decoded.config
                )
            )
        } catch {
            let data = (try? Data(contentsOf: url)) ?? Data()
            return .invalid(data, error)
        }
    }

    private func acceptLoadedSnapshot(_ snapshot: StoredConfigSnapshot) throws -> AppConfig {
        if snapshot.source == .primary {
            if snapshot.wasMigrated {
                log("Loaded primary config and migrated site defaults before rewriting persisted snapshots")
                try save(snapshot.config)
                return snapshot.config
            }
            try syncShadowCopiesIfNeeded(primaryData: snapshot.rawData)
            return snapshot.config
        }

        log("Recovered config from \(snapshot.source.rawValue) snapshot")
        try save(snapshot.config)
        return snapshot.config
    }

    private func acceptLossySnapshot(
        _ snapshot: StoredConfigSnapshot,
        diagnostics: AppConfigDecodeDiagnostics
    ) throws -> AppConfig {
        lastLoadWasLossy = true
        try preserveFallbackCandidateIfNeeded(snapshot.rawData)
        log(
            "Loaded lossy \(snapshot.source.rawValue) config in-place; provider decoding dropped \(diagnostics.droppedProviderEntryCount) entries"
        )
        return snapshot.config
    }

    private func syncShadowCopiesIfNeeded(primaryData: Data) throws {
        if !fileManager.fileExists(atPath: backupFileURL.path) {
            try writeData(primaryData, to: backupFileURL)
        }
        if !fileManager.fileExists(atPath: recoveryFileURL.path) {
            try writeData(primaryData, to: recoveryFileURL)
        }
        try writeLastKnownGoodIfEligible(primaryData, overwriteExisting: false)
    }

    private func writeLastKnownGoodIfEligible(_ data: Data, overwriteExisting: Bool) throws {
        if !overwriteExisting, fileManager.fileExists(atPath: lastKnownGoodFileURL.path) {
            return
        }
        let decoded = try AppConfig.decodeWithDiagnostics(from: data)
        guard !decoded.diagnostics.hadLossyProviderDecoding else {
            log(
                "Skipped updating last-known-good snapshot because provider decoding dropped \(decoded.diagnostics.droppedProviderEntryCount) entries"
            )
            return
        }
        try writeData(data, to: lastKnownGoodFileURL)
    }

    private func recoverFromPersistedOfficialStateAndRestoreIfNeeded() throws -> AppConfig? {
        guard let recovered = recoveredConfigFromPersistedOfficialState() else {
            return nil
        }
        try save(recovered, updateLastKnownGood: false, clearPreservedFallbackCandidate: false)
        return recovered
    }

    private func recoveredConfigFromPersistedOfficialState() -> AppConfig? {
        let directory = fileURL.deletingLastPathComponent()
        var recovered = AppConfig.default
        var restoredProviderIDs: [String] = []

        for state in PersistedOfficialState.allCases where hasPersistedState(for: state, in: directory) {
            guard let index = recovered.providers.firstIndex(where: { $0.id == state.providerID }) else {
                continue
            }
            recovered.providers[index].enabled = true
            restoredProviderIDs.append(state.providerID)
        }

        guard !restoredProviderIDs.isEmpty else {
            return nil
        }

        return recovered.migratedWithSiteDefaults()
    }

    private func hasPersistedState(for state: PersistedOfficialState, in directory: URL) -> Bool {
        switch state {
        case .codex:
            let profileStore = CodexAccountProfileStore(
                fileManager: fileManager,
                fileURL: directory.appendingPathComponent("codex_profiles.json")
            )
            if !profileStore.profiles().isEmpty {
                return true
            }
            let slotStore = CodexAccountSlotStore(
                fileManager: fileManager,
                staleInterval: .greatestFiniteMagnitude,
                fileURL: directory.appendingPathComponent("codex_slots.json")
            )
            return !slotStore.visibleSlots().isEmpty
        case .claude:
            let profileStore = ClaudeAccountProfileStore(
                fileManager: fileManager,
                fileURL: directory.appendingPathComponent("claude_profiles.json")
            )
            if !profileStore.profiles().isEmpty {
                return true
            }
            let slotStore = ClaudeAccountSlotStore(
                fileManager: fileManager,
                staleInterval: .greatestFiniteMagnitude,
                fileURL: directory.appendingPathComponent("claude_slots.json")
            )
            return !slotStore.visibleSlots().isEmpty
        }
    }

    private func log(_ message: String) {
        NSLog("[ConfigStore] %@", message)
    }

    private func loadOrder() -> [(PersistedConfigSource, URL)] {
        if fileManager.fileExists(atPath: preservedFallbackCandidateFileURL.path) {
            return [
                (.lastKnownGood, lastKnownGoodFileURL),
                (.preservedFallbackCandidate, preservedFallbackCandidateFileURL),
                (.primary, fileURL),
                (.backup, backupFileURL),
                (.recovery, recoveryFileURL)
            ]
        }

        return [
            (.primary, fileURL),
            (.backup, backupFileURL),
            (.recovery, recoveryFileURL),
            (.lastKnownGood, lastKnownGoodFileURL)
        ]
    }

    private func preserveFallbackCandidateIfNeeded(_ data: Data?) throws {
        guard let data, !data.isEmpty else { return }
        try writeData(data, to: preservedFallbackCandidateFileURL)
    }

    private func removePreservedFallbackCandidateIfPresent() throws {
        if fileManager.fileExists(atPath: preservedFallbackCandidateFileURL.path) {
            try fileManager.removeItem(at: preservedFallbackCandidateFileURL)
        }
    }
}
