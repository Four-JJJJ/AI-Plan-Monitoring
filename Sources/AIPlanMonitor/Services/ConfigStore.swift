import Foundation

final class ConfigStore {
    private static let legacyImportBackupDirectoryPrefix = "legacy-import-backup-aibalancemonitor-"
    private static let legacySupplementalFilenames = [
        "codex_profiles.json",
        "codex_slots.json",
        "claude_profiles.json",
        "claude_slots.json",
        "third_party_balance_baselines.json",
        "local_usage_history_cache.json"
    ]

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

    private struct LegacyImportMergeResult {
        let config: AppConfig
        let importedRelayCount: Int
    }

    private struct LegacySettingEligibility {
        let language: Bool
        let launchAtLoginEnabled: Bool
        let showOfficialAccountEmailInMenuBar: Bool
        let statusBarProviderID: Bool
        let statusBarMultiUsageEnabled: Bool
        let statusBarMultiProviderIDs: Bool
        let statusBarAppearanceMode: Bool
        let statusBarDisplayStyle: Bool
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

    private let directoryURL: URL
    private let legacyDirectoryURL: URL
    private let fileURL: URL
    private let backupFileURL: URL
    private let recoveryFileURL: URL
    private let lastKnownGoodFileURL: URL
    private let preservedFallbackCandidateFileURL: URL
    private let legacyImportMarkerFileURL: URL
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
        self.directoryURL = directory
        self.legacyDirectoryURL = rootDirectory.appendingPathComponent("AIBalanceMonitor", isDirectory: true)
        self.fileURL = directory.appendingPathComponent("config.json")
        self.backupFileURL = directory.appendingPathComponent("config.backup.json")
        self.recoveryFileURL = directory.appendingPathComponent("config.recovery.json")
        self.lastKnownGoodFileURL = directory.appendingPathComponent("config.last-known-good.json")
        self.preservedFallbackCandidateFileURL = directory.appendingPathComponent("config.preserved-fallback-candidate.json")
        self.legacyImportMarkerFileURL = directory.appendingPathComponent("legacy-import-aibalancemonitor.done")
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
                    let loaded = try acceptLoadedSnapshot(snapshot)
                    return applyLegacyImportIfNeeded(to: loaded)
                }
            }

            if let lossySnapshot {
                let loaded = try acceptLossySnapshot(lossySnapshot.snapshot, diagnostics: lossySnapshot.diagnostics)
                return applyLegacyImportIfNeeded(to: loaded)
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
                let loaded = try acceptLoadedSnapshot(snapshot)
                return applyLegacyImportIfNeeded(to: loaded)
            }
        }

        if let recovered = try recoverFromPersistedOfficialStateAndRestoreIfNeeded() {
            try preserveFallbackCandidateIfNeeded(preservedFallbackData)
            log("Recovered official monitoring state from persisted profiles/slots")
            return applyLegacyImportIfNeeded(to: recovered)
        }

        let defaultConfig = AppConfig.default
        try preserveFallbackCandidateIfNeeded(preservedFallbackData)
        try save(defaultConfig)
        if sawPersistedConfigSource {
            log("Fell back to default config after all persisted config sources were invalid or lossy")
        } else {
            log("No persisted config found; wrote default config")
        }
        return applyLegacyImportIfNeeded(to: defaultConfig)
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
        if fileManager.fileExists(atPath: legacyImportMarkerFileURL.path) {
            try fileManager.removeItem(at: legacyImportMarkerFileURL)
        }
        for url in legacyImportBackupDirectories() {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
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
        var recovered = AppConfig.default
        var restoredProviderIDs: [String] = []

        for state in PersistedOfficialState.allCases where hasPersistedState(for: state, in: directoryURL) {
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

    private func applyLegacyImportIfNeeded(to currentConfig: AppConfig) -> AppConfig {
        guard !fileManager.fileExists(atPath: legacyImportMarkerFileURL.path) else {
            return currentConfig
        }
        guard fileManager.fileExists(atPath: legacyDirectoryURL.path) else {
            return currentConfig
        }

        do {
            let legacyConfig = loadLegacyConfigIfAvailable()
            let filesToCopy = legacySupplementalFilesToCopy()
            let mergeResult = legacyConfig.map { mergeLegacyConfig($0, into: currentConfig) }
            let mergedConfig = mergeResult?.config ?? currentConfig
            let configChanged = mergedConfig != currentConfig
            let shouldWriteMarker = legacyConfig != nil || !filesToCopy.isEmpty

            guard configChanged || !filesToCopy.isEmpty || shouldWriteMarker else {
                return currentConfig
            }

            if configChanged || !filesToCopy.isEmpty {
                try snapshotCurrentDirectoryForLegacyImport()
            }
            if configChanged {
                try save(mergedConfig)
            }
            try copyLegacySupplementalFiles(filesToCopy)
            try writeLegacyImportMarker()

            if let mergeResult {
                log(
                    "Imported legacy AIBalanceMonitor data (\(mergeResult.importedRelayCount) relay providers, \(filesToCopy.count) supplemental files)"
                )
            } else if !filesToCopy.isEmpty {
                log("Copied \(filesToCopy.count) legacy AIBalanceMonitor supplemental files")
            } else {
                log("Marked legacy AIBalanceMonitor import as evaluated with no data changes")
            }
            return mergedConfig
        } catch {
            log("Skipped legacy AIBalanceMonitor import: \(error.localizedDescription)")
            return currentConfig
        }
    }

    private func loadLegacyConfigIfAvailable() -> AppConfig? {
        let legacyConfigURL = legacyDirectoryURL.appendingPathComponent("config.json")
        guard fileManager.fileExists(atPath: legacyConfigURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: legacyConfigURL)
            let decoded = try AppConfig.decodeWithDiagnostics(from: data)
            guard !decoded.diagnostics.hadLossyProviderDecoding else {
                log(
                    "Ignoring legacy AIBalanceMonitor config because provider decoding dropped \(decoded.diagnostics.droppedProviderEntryCount) entries"
                )
                return nil
            }
            return decoded.config.migratedWithSiteDefaults()
        } catch {
            log("Ignoring legacy AIBalanceMonitor config because it could not be decoded: \(error.localizedDescription)")
            return nil
        }
    }

    private func mergeLegacyConfig(_ legacyConfig: AppConfig, into currentConfig: AppConfig) -> LegacyImportMergeResult {
        var merged = currentConfig
        let eligibility = legacySettingEligibility(for: currentConfig)
        var resolvedLegacyProviderIDs: [String: String] = [:]
        var importedRelayCount = 0

        for provider in legacyConfig.providers {
            guard provider.family == .thirdParty,
                  provider.isRelay,
                  !provider.isLegacyRelayExample else {
                continue
            }

            let normalizedLegacy = provider.normalized()
            guard let legacyIdentity = normalizedLegacy.legacyRelayImportIdentity else {
                continue
            }

            if let existingIndex = merged.providers.firstIndex(where: { $0.legacyRelayImportIdentity == legacyIdentity }) {
                merged.providers[existingIndex] = mergedLegacyRelayProvider(
                    current: merged.providers[existingIndex],
                    legacy: normalizedLegacy
                )
                resolvedLegacyProviderIDs[provider.id] = merged.providers[existingIndex].id
                continue
            }

            merged.providers.append(normalizedLegacy)
            resolvedLegacyProviderIDs[provider.id] = normalizedLegacy.id
            importedRelayCount += 1
        }

        mergeLegacyTopLevelSettings(
            from: legacyConfig,
            into: &merged,
            eligibility: eligibility,
            resolvedLegacyProviderIDs: resolvedLegacyProviderIDs
        )

        return LegacyImportMergeResult(
            config: merged.migratedWithSiteDefaults(),
            importedRelayCount: importedRelayCount
        )
    }

    private func legacySettingEligibility(for currentConfig: AppConfig) -> LegacySettingEligibility {
        let defaultStatusBarProviderID = AppConfig.defaultStatusBarProviderID(from: currentConfig.providers)
        let defaultMultiProviderIDs = defaultStatusBarProviderID.map { [$0] } ?? []
        return LegacySettingEligibility(
            language: currentConfig.language == AppConfig.default.language,
            launchAtLoginEnabled: currentConfig.launchAtLoginEnabled == AppConfig.default.launchAtLoginEnabled,
            showOfficialAccountEmailInMenuBar: currentConfig.showOfficialAccountEmailInMenuBar == AppConfig.default.showOfficialAccountEmailInMenuBar,
            statusBarProviderID: currentConfig.statusBarProviderID == nil || currentConfig.statusBarProviderID == defaultStatusBarProviderID,
            statusBarMultiUsageEnabled: currentConfig.statusBarMultiUsageEnabled == AppConfig.default.statusBarMultiUsageEnabled,
            statusBarMultiProviderIDs: currentConfig.statusBarMultiProviderIDs.isEmpty || currentConfig.statusBarMultiProviderIDs == defaultMultiProviderIDs,
            statusBarAppearanceMode: currentConfig.statusBarAppearanceMode == AppConfig.default.statusBarAppearanceMode,
            statusBarDisplayStyle: currentConfig.statusBarDisplayStyle == AppConfig.default.statusBarDisplayStyle
        )
    }

    private func mergeLegacyTopLevelSettings(
        from legacyConfig: AppConfig,
        into mergedConfig: inout AppConfig,
        eligibility: LegacySettingEligibility,
        resolvedLegacyProviderIDs: [String: String]
    ) {
        if eligibility.language {
            mergedConfig.language = legacyConfig.language
        }
        if eligibility.launchAtLoginEnabled {
            mergedConfig.launchAtLoginEnabled = legacyConfig.launchAtLoginEnabled
        }
        if eligibility.showOfficialAccountEmailInMenuBar {
            mergedConfig.showOfficialAccountEmailInMenuBar = legacyConfig.showOfficialAccountEmailInMenuBar
        }

        let resolvedStatusBarProviderID = resolvedLegacyProviderID(
            legacyConfig.statusBarProviderID,
            mergedProviders: mergedConfig.providers,
            resolvedLegacyProviderIDs: resolvedLegacyProviderIDs
        )
        let resolvedMultiProviderIDs = legacyConfig.statusBarMultiProviderIDs.compactMap { legacyProviderID in
            resolvedLegacyProviderID(
                legacyProviderID,
                mergedProviders: mergedConfig.providers,
                resolvedLegacyProviderIDs: resolvedLegacyProviderIDs
            )
        }

        if eligibility.statusBarProviderID,
           let resolvedStatusBarProviderID {
            mergedConfig.statusBarProviderID = resolvedStatusBarProviderID
        }
        if eligibility.statusBarMultiProviderIDs,
           !resolvedMultiProviderIDs.isEmpty {
            mergedConfig.statusBarMultiProviderIDs = resolvedMultiProviderIDs
        }
        if eligibility.statusBarMultiUsageEnabled {
            mergedConfig.statusBarMultiUsageEnabled = legacyConfig.statusBarMultiUsageEnabled && !resolvedMultiProviderIDs.isEmpty
        }
        if eligibility.statusBarAppearanceMode {
            mergedConfig.statusBarAppearanceMode = legacyConfig.statusBarAppearanceMode
        }
        if eligibility.statusBarDisplayStyle {
            mergedConfig.statusBarDisplayStyle = legacyConfig.statusBarDisplayStyle
        }
    }

    private func resolvedLegacyProviderID(
        _ legacyProviderID: String?,
        mergedProviders: [ProviderDescriptor],
        resolvedLegacyProviderIDs: [String: String]
    ) -> String? {
        guard let legacyProviderID else {
            return nil
        }

        let resolved = resolvedLegacyProviderIDs[legacyProviderID] ?? legacyProviderID
        return mergedProviders.contains(where: { $0.id == resolved }) ? resolved : nil
    }

    private func mergedLegacyRelayProvider(
        current: ProviderDescriptor,
        legacy: ProviderDescriptor
    ) -> ProviderDescriptor {
        var merged = current

        if merged.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.name = legacy.name
        }
        if (merged.baseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.baseURL = legacy.baseURL
        }
        if merged.auth.kind == .none {
            merged.auth.kind = legacy.auth.kind
        }
        merged.auth = mergedAuth(current: merged.auth, legacy: legacy.auth)

        if merged.pollIntervalSec <= 0 {
            merged.pollIntervalSec = legacy.pollIntervalSec
        }

        if merged.relayConfig == nil {
            merged.relayConfig = legacy.relayConfig
            return merged.normalized()
        }

        if var currentRelay = merged.relayConfig,
           let legacyRelay = legacy.relayConfig {
            let currentAdapterID = currentRelay.adapterID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if currentAdapterID.isEmpty {
                currentRelay.adapterID = legacyRelay.adapterID
            }
            if currentRelay.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                currentRelay.baseURL = legacyRelay.baseURL
            }
            currentRelay.balanceAuth = mergedAuth(current: currentRelay.balanceAuth, legacy: legacyRelay.balanceAuth)
            if currentRelay.balanceCredentialMode == nil {
                currentRelay.balanceCredentialMode = legacyRelay.balanceCredentialMode
            }
            if currentRelay.manualOverrides == nil {
                currentRelay.manualOverrides = legacyRelay.manualOverrides
            }
            merged.relayConfig = currentRelay
        }

        return merged.normalized()
    }

    private func legacySupplementalFilesToCopy() -> [(source: URL, destination: URL)] {
        Self.legacySupplementalFilenames.compactMap { filename in
            let sourceURL = legacyDirectoryURL.appendingPathComponent(filename)
            let destinationURL = directoryURL.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: sourceURL.path),
                  !fileManager.fileExists(atPath: destinationURL.path) else {
                return nil
            }
            return (sourceURL, destinationURL)
        }
    }

    private func copyLegacySupplementalFiles(_ files: [(source: URL, destination: URL)]) throws {
        for file in files {
            try fileManager.copyItem(at: file.source, to: file.destination)
        }
    }

    private func snapshotCurrentDirectoryForLegacyImport() throws {
        let backupDirectoryURL = directoryURL.appendingPathComponent(
            "\(Self.legacyImportBackupDirectoryPrefix)\(Int(Date().timeIntervalSince1970))",
            isDirectory: true
        )
        try fileManager.createDirectory(at: backupDirectoryURL, withIntermediateDirectories: true)

        let existingFiles = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for fileURL in existingFiles {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }
            try fileManager.copyItem(at: fileURL, to: backupDirectoryURL.appendingPathComponent(fileURL.lastPathComponent))
        }
    }

    private func writeLegacyImportMarker() throws {
        try ensureDirectoryExists()
        let note = "importedAt=\(ISO8601DateFormatter().string(from: Date()))\n"
        try writeData(Data(note.utf8), to: legacyImportMarkerFileURL)
    }

    private func legacyImportBackupDirectories() -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.filter { url in
            let isBackupDirectory = url.lastPathComponent.hasPrefix(Self.legacyImportBackupDirectoryPrefix)
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isBackupDirectory && isDirectory
        }
    }

    private func mergedAuth(current: AuthConfig, legacy: AuthConfig) -> AuthConfig {
        AuthConfig(
            kind: current.kind == .none ? legacy.kind : current.kind,
            keychainService: current.keychainService ?? legacy.keychainService,
            keychainAccount: current.keychainAccount ?? legacy.keychainAccount
        )
    }
}
