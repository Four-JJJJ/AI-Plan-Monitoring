import Foundation
import OhMyUsageDomain

final class LegacyConfigImporter {
    private enum LegacyConfigLoadResult {
        case missing
        case invalid
        case usable(AppConfig)
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

    private static let supplementalFilenames = [
        "codex_profiles.json",
        "codex_slots.json",
        "claude_profiles.json",
        "claude_slots.json",
        "third_party_balance_baselines.json",
        "local_usage_history_cache.json"
    ]

    private let directoryURL: URL
    private let sources: [LegacyConfigSource]
    private let fileManager: FileManager
    private let saveConfig: (AppConfig) throws -> Void
    private let log: (String) -> Void

    init(
        paths: ConfigStorePaths,
        fileManager: FileManager,
        saveConfig: @escaping (AppConfig) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.directoryURL = paths.directoryURL
        self.sources = paths.legacyConfigSources
        self.fileManager = fileManager
        self.saveConfig = saveConfig
        self.log = log
    }

    func applyIfNeeded(to currentConfig: AppConfig) -> AppConfig {
        var importedConfig = currentConfig
        for source in sources {
            importedConfig = applyIfNeeded(from: source, to: importedConfig)
        }
        return importedConfig
    }

    func backupDirectories() -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let backupPrefixes = Set(sources.map(\.backupDirectoryPrefix))
        return urls.filter { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDirectory && backupPrefixes.contains(where: { url.lastPathComponent.hasPrefix($0) })
        }
    }

    private func applyIfNeeded(
        from source: LegacyConfigSource,
        to currentConfig: AppConfig
    ) -> AppConfig {
        if fileManager.fileExists(atPath: source.importMarkerFileURL.path) {
            cleanupSourceDirectoryIfNeeded(from: source)
            return currentConfig
        }
        guard fileManager.fileExists(atPath: source.directoryURL.path) else {
            return currentConfig
        }

        do {
            let legacyConfig: AppConfig?
            switch loadConfig(from: source) {
            case .missing:
                legacyConfig = nil
            case .invalid:
                return currentConfig
            case .usable(let config):
                legacyConfig = config
            }
            let filesToCopy = supplementalFilesToCopy(from: source)
            let mergeResult = legacyConfig.map { mergeConfig($0, into: currentConfig) }
            let mergedConfig = mergeResult?.config ?? currentConfig
            let configChanged = mergedConfig != currentConfig
            let shouldWriteMarker = legacyConfig != nil || !filesToCopy.isEmpty

            guard configChanged || !filesToCopy.isEmpty || shouldWriteMarker else {
                return currentConfig
            }

            if configChanged || !filesToCopy.isEmpty {
                try snapshotCurrentDirectory(from: source)
            }
            if configChanged {
                try saveConfig(mergedConfig)
            }
            try copySupplementalFiles(filesToCopy)
            try writeImportMarker(for: source)
            cleanupSourceDirectoryIfNeeded(from: source)

            if let mergeResult {
                log(
                    "Imported legacy \(source.displayName) data (\(mergeResult.importedRelayCount) relay providers, \(filesToCopy.count) supplemental files)"
                )
            } else if !filesToCopy.isEmpty {
                log("Copied \(filesToCopy.count) legacy \(source.displayName) supplemental files")
            } else {
                log("Marked legacy \(source.displayName) import as evaluated with no data changes")
            }
            return mergedConfig
        } catch {
            log("Skipped legacy \(source.displayName) import: \(error.localizedDescription)")
            return currentConfig
        }
    }

    private func loadConfig(from source: LegacyConfigSource) -> LegacyConfigLoadResult {
        let legacyConfigURL = source.directoryURL.appendingPathComponent("config.json")
        guard fileManager.fileExists(atPath: legacyConfigURL.path) else {
            return .missing
        }

        do {
            let data = try Data(contentsOf: legacyConfigURL)
            let decoded = try AppConfig.decodeWithDiagnostics(from: data)
            guard !decoded.diagnostics.hadLossyProviderDecoding else {
                log(
                    "Ignoring legacy \(source.displayName) config because provider decoding dropped \(decoded.diagnostics.droppedProviderEntryCount) entries"
                )
                return .invalid
            }
            return .usable(decoded.config.migratedWithSiteDefaults())
        } catch {
            log("Ignoring legacy \(source.displayName) config because it could not be decoded: \(error.localizedDescription)")
            return .invalid
        }
    }

    private func mergeConfig(_ legacyConfig: AppConfig, into currentConfig: AppConfig) -> LegacyImportMergeResult {
        var merged = currentConfig
        let eligibility = legacySettingEligibility(for: currentConfig)
        var resolvedLegacyProviderIDs: [String: String] = [:]
        var importedRelayCount = 0

        for provider in legacyConfig.providers {
            let normalizedLegacy = provider.normalized()

            if normalizedLegacy.isOfficialRelayProvider {
                let targetID = normalizedLegacy.officialRelayDefaultProviderID ?? normalizedLegacy.id
                var legacyOfficialRelay = normalizedLegacy
                legacyOfficialRelay.id = targetID
                legacyOfficialRelay.family = .official
                legacyOfficialRelay.officialConfig = nil

                if let existingIndex = merged.providers.firstIndex(where: { $0.id == targetID }) {
                    let wasEnabled = merged.providers[existingIndex].enabled
                    merged.providers[existingIndex] = mergedLegacyOfficialRelayProvider(
                        current: merged.providers[existingIndex],
                        legacy: legacyOfficialRelay
                    )
                    if legacyOfficialRelay.enabled && !wasEnabled {
                        importedRelayCount += 1
                    }
                } else {
                    merged.providers.append(legacyOfficialRelay)
                    if legacyOfficialRelay.enabled {
                        importedRelayCount += 1
                    }
                }
                resolvedLegacyProviderIDs[provider.id] = targetID
                continue
            }

            guard normalizedLegacy.family == .thirdParty,
                  normalizedLegacy.isRelay,
                  !normalizedLegacy.isLegacyRelayExample else {
                continue
            }

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

    private func mergedLegacyOfficialRelayProvider(
        current: ProviderDescriptor,
        legacy: ProviderDescriptor
    ) -> ProviderDescriptor {
        var merged = current
        merged.family = .official
        merged.type = .relay
        merged.officialConfig = nil
        merged.openConfig = nil

        if legacy.enabled {
            merged.enabled = true
            if legacy.pollIntervalSec > 0 {
                merged.pollIntervalSec = legacy.pollIntervalSec
            }
            merged.threshold = legacy.threshold
            merged.auth = mergedAuth(current: legacy.auth, legacy: current.auth)
            if let baseURL = legacy.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
               !baseURL.isEmpty {
                merged.baseURL = baseURL
            }
            if let legacyRelay = legacy.relayConfig {
                merged.relayConfig = legacyRelay
            }
        } else {
            merged.enabled = current.enabled
            merged.auth = mergedAuth(current: current.auth, legacy: legacy.auth)
            if (merged.baseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                merged.baseURL = legacy.baseURL
            }
            if merged.relayConfig == nil {
                merged.relayConfig = legacy.relayConfig
            }
        }

        if let adapterID = merged.officialRelayAdapterID,
           let displayName = ProviderDescriptor.officialRelayDisplayName(adapterID: adapterID) {
            merged.name = displayName
        } else if merged.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.name = legacy.name
        }

        return merged.normalized()
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

    private func supplementalFilesToCopy(from source: LegacyConfigSource) -> [(source: URL, destination: URL)] {
        Self.supplementalFilenames.compactMap { filename in
            let sourceURL = source.directoryURL.appendingPathComponent(filename)
            let destinationURL = directoryURL.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: sourceURL.path),
                  !fileManager.fileExists(atPath: destinationURL.path) else {
                return nil
            }
            return (sourceURL, destinationURL)
        }
    }

    private func copySupplementalFiles(_ files: [(source: URL, destination: URL)]) throws {
        for file in files {
            try fileManager.copyItem(at: file.source, to: file.destination)
        }
    }

    private func snapshotCurrentDirectory(from source: LegacyConfigSource) throws {
        let backupDirectoryURL = directoryURL.appendingPathComponent(
            "\(source.backupDirectoryPrefix)\(Int(Date().timeIntervalSince1970))",
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

    private func writeImportMarker(for source: LegacyConfigSource) throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        let note = "importedAt=\(ISO8601DateFormatter().string(from: Date()))\n"
        try Data(note.utf8).write(to: source.importMarkerFileURL, options: .atomic)
    }

    private func cleanupSourceDirectoryIfNeeded(from source: LegacyConfigSource) {
        guard fileManager.fileExists(atPath: source.directoryURL.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: source.directoryURL)
            log("Removed legacy \(source.displayName) data directory after migration")
        } catch {
            log("Could not remove legacy \(source.displayName) data directory; will retry on next launch: \(error.localizedDescription)")
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
