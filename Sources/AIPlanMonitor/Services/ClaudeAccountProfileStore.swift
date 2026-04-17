import CryptoKit
import Foundation

enum ClaudeAccountProfileError: LocalizedError {
    case invalidCredentialsJSON
    case missingAccessToken
    case missingConfigDirectory
    case missingCredentialsFile(String)
    case missingStoredCredentials

    var errorDescription: String? {
        switch self {
        case .invalidCredentialsJSON:
            return "Invalid Claude credentials JSON"
        case .missingAccessToken:
            return "Claude credentials JSON is missing access token"
        case .missingConfigDirectory:
            return "Claude config directory is required"
        case .missingCredentialsFile(let path):
            return "Unable to read Claude credentials at \(path)"
        case .missingStoredCredentials:
            return "No stored Claude credentials"
        }
    }
}

struct ClaudeParsedCredentialsPayload {
    var accessToken: String
    var refreshToken: String?
    var expiresAtMs: Double?
    var subscriptionType: String?
    var scopes: [String]
    var accountId: String?
    var accountEmail: String?
    var credentialFingerprint: String
}

final class ClaudeAccountProfileStore {
    private struct ProfileFile: Codable {
        var profiles: [ClaudeAccountProfile]
        var ignoredFingerprints: [String]?
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
            self.fileURL = directory.appendingPathComponent("claude_profiles.json")
        }
    }

    func profiles() -> [ClaudeAccountProfile] {
        load().sorted { $0.slotID < $1.slotID }
    }

    func profile(slotID: CodexSlotID) -> ClaudeAccountProfile? {
        load().first(where: { $0.slotID == slotID })
    }

    func nextAvailableSlotID() -> CodexSlotID {
        let existing = Set(load().map(\.slotID))
        return CodexSlotID.nextAvailable(excluding: existing)
    }

    @discardableResult
    func saveProfile(
        slotID: CodexSlotID,
        displayName: String,
        source: ClaudeProfileSource,
        configDir: String?,
        credentialsJSON: String?,
        currentFingerprint: String?
    ) throws -> ClaudeAccountProfile {
        let resolvedConfigDir = Self.normalizedConfigDirectory(configDir)
        let resolvedCredentialsJSON = try Self.resolveCredentialsJSON(
            source: source,
            configDir: resolvedConfigDir,
            credentialsJSON: credentialsJSON
        )
        let payload = try Self.parseCredentialsJSON(resolvedCredentialsJSON)

        var items = load()
        var ignoredFingerprints = loadIgnoredFingerprints()
        ignoredFingerprints.remove(payload.credentialFingerprint.lowercased())

        var profile = ClaudeAccountProfile(
            slotID: slotID,
            displayName: Self.fallbackDisplayName(displayName, slotID: slotID),
            source: source,
            configDir: resolvedConfigDir,
            credentialsJSON: source == .manualCredentials ? resolvedCredentialsJSON : resolvedCredentialsJSON,
            accountId: payload.accountId,
            accountEmail: payload.accountEmail,
            credentialFingerprint: payload.credentialFingerprint,
            lastImportedAt: Date(),
            isCurrentSystemAccount: payload.credentialFingerprint.lowercased() == currentFingerprint?.lowercased()
        )
        profile = normalizedProfile(profile)

        if let matched = Self.matchingIndex(for: payload, in: items),
           items[matched].slotID != slotID {
            items.remove(at: matched)
        }

        if let existing = items.firstIndex(where: { $0.slotID == slotID }) {
            profile.lastImportedAt = Date()
            items[existing] = profile
        } else {
            items.append(profile)
        }

        try save(items, ignoredFingerprints: ignoredFingerprints)
        return profile
    }

    @discardableResult
    func updateStoredCredentials(slotID: CodexSlotID, credentialsJSON: String) -> ClaudeAccountProfile? {
        let trimmed = credentialsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let payload = try? Self.parseCredentialsJSON(trimmed) else { return nil }

        var items = load()
        guard let index = items.firstIndex(where: { $0.slotID == slotID }) else { return nil }
        var profile = items[index]
        profile.credentialsJSON = trimmed
        profile.accountId = payload.accountId
        profile.accountEmail = payload.accountEmail
        profile.credentialFingerprint = payload.credentialFingerprint
        profile.lastImportedAt = Date()
        profile = normalizedProfile(profile)
        items[index] = profile
        try? save(items, ignoredFingerprints: loadIgnoredFingerprints())
        return profile
    }

    @discardableResult
    func removeProfile(slotID: CodexSlotID) -> [ClaudeAccountProfile] {
        var items = load()
        var ignoredFingerprints = loadIgnoredFingerprints()
        if let removed = items.first(where: { $0.slotID == slotID })?.credentialFingerprint?.lowercased(),
           !removed.isEmpty {
            ignoredFingerprints.insert(removed)
        }
        items.removeAll { $0.slotID == slotID }
        try? save(items, ignoredFingerprints: ignoredFingerprints)
        return items.sorted { $0.slotID < $1.slotID }
    }

    @discardableResult
    func updateCurrentFingerprint(_ fingerprint: String?) -> [ClaudeAccountProfile] {
        var items = load()
        let normalizedCurrentFingerprint = fingerprint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var changed = false
        for index in items.indices {
            let isCurrent = items[index].credentialFingerprint?.lowercased() == normalizedCurrentFingerprint
                && normalizedCurrentFingerprint != nil
            if items[index].isCurrentSystemAccount != isCurrent {
                items[index].isCurrentSystemAccount = isCurrent
                changed = true
            }
        }
        if changed {
            try? save(items, ignoredFingerprints: loadIgnoredFingerprints())
        }
        return items.sorted { $0.slotID < $1.slotID }
    }

    @discardableResult
    func captureCurrentCredentialsIfNeeded(
        credentialsJSON: String?,
        defaultConfigDir: String?,
        preferredAutoSlots: [CodexSlotID] = [.a, .b]
    ) -> [ClaudeAccountProfile] {
        guard let credentialsJSON else {
            return updateCurrentFingerprint(nil)
        }

        let trimmed = credentialsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let payload = try? Self.parseCredentialsJSON(trimmed) else {
            return updateCurrentFingerprint(nil)
        }

        var items = load()
        let currentFingerprint = payload.credentialFingerprint.lowercased()
        let ignoredFingerprints = loadIgnoredFingerprints()
        if ignoredFingerprints.contains(currentFingerprint) {
            return updateCurrentFingerprint(currentFingerprint)
        }

        let normalizedConfigDir = Self.normalizedConfigDirectory(defaultConfigDir) ?? Self.defaultClaudeConfigDirectory()
        if let existing = Self.matchingIndex(for: payload, in: items) {
            var profile = items[existing]
            if profile.source == .configDir {
                profile.configDir = normalizedConfigDir
            }
            profile.credentialsJSON = trimmed
            profile.accountId = payload.accountId
            profile.accountEmail = payload.accountEmail
            profile.credentialFingerprint = payload.credentialFingerprint
            profile.lastImportedAt = Date()
            items[existing] = normalizedProfile(profile)
            try? save(items, ignoredFingerprints: ignoredFingerprints)
            return updateCurrentFingerprint(currentFingerprint)
        }

        let occupied = Set(items.map(\.slotID))
        let slotID = preferredAutoSlots.first(where: { !occupied.contains($0) })
            ?? CodexSlotID.nextAvailable(excluding: occupied)

        items.append(
            ClaudeAccountProfile(
                slotID: slotID,
                displayName: "Claude \(slotID.rawValue)",
                source: .configDir,
                configDir: normalizedConfigDir,
                credentialsJSON: trimmed,
                accountId: payload.accountId,
                accountEmail: payload.accountEmail,
                credentialFingerprint: payload.credentialFingerprint,
                lastImportedAt: Date(),
                isCurrentSystemAccount: true
            )
        )
        try? save(items, ignoredFingerprints: ignoredFingerprints)
        return updateCurrentFingerprint(currentFingerprint)
    }

    func reset() {
        try? fileManager.removeItem(at: fileURL)
    }

    func resolvedCredentialsJSON(for profile: ClaudeAccountProfile) throws -> String {
        try Self.resolvedCredentialsJSON(for: profile)
    }

    static func resolvedCredentialsJSON(for profile: ClaudeAccountProfile) throws -> String {
        let normalizedConfigDir = normalizedConfigDirectory(profile.configDir)
        let cached = profile.credentialsJSON?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch profile.source {
        case .configDir:
            if let normalizedConfigDir,
               let fromDirectory = try? loadCredentialsJSON(fromConfigDirectory: normalizedConfigDir) {
                return fromDirectory
            }
            if let cached, !cached.isEmpty {
                return cached
            }
            throw ClaudeAccountProfileError.missingStoredCredentials
        case .manualCredentials:
            if let cached, !cached.isEmpty {
                return cached
            }
            if let normalizedConfigDir,
               let fromDirectory = try? loadCredentialsJSON(fromConfigDirectory: normalizedConfigDir) {
                return fromDirectory
            }
            throw ClaudeAccountProfileError.missingStoredCredentials
        }
    }

    static func parseCredentialsJSON(_ raw: String) throws -> ClaudeParsedCredentialsPayload {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeAccountProfileError.invalidCredentialsJSON
        }

        let oauth = (json["claudeAiOauth"] as? [String: Any]) ?? json
        guard let accessToken = OfficialValueParser.string(
            oauth["accessToken"] ?? oauth["access_token"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !accessToken.isEmpty else {
            throw ClaudeAccountProfileError.missingAccessToken
        }

        let refreshToken = OfficialValueParser.string(
            oauth["refreshToken"] ?? oauth["refresh_token"]
        )
        let expiresAtMs = OfficialValueParser.double(oauth["expiresAt"] ?? oauth["expires_at"])
        let subscriptionType = OfficialValueParser.string(oauth["subscriptionType"] ?? oauth["subscription_type"])
        let scopes = (oauth["scopes"] as? [String]) ?? []
        let accountId = OfficialValueParser.string(
            json["accountId"] ?? json["account_id"] ?? oauth["accountId"] ?? oauth["account_id"]
        )
        let accountEmail = Self.extractAccountEmail(from: json, oauth: oauth)
        let fingerprint = credentialFingerprint(for: accessToken)
            ?? credentialFingerprint(for: trimmed)
            ?? UUID().uuidString

        return ClaudeParsedCredentialsPayload(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAtMs: expiresAtMs,
            subscriptionType: subscriptionType,
            scopes: scopes,
            accountId: accountId,
            accountEmail: accountEmail,
            credentialFingerprint: fingerprint
        )
    }

    static func credentialFingerprint(for raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func normalizedConfigDirectory(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        let standard = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL.path
        return standard
    }

    static func defaultClaudeConfigDirectory() -> String {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .path
    }

    static func credentialsFilePath(configDirectory: String) -> String {
        URL(fileURLWithPath: configDirectory, isDirectory: true)
            .appendingPathComponent(".credentials.json")
            .path
    }

    static func loadCredentialsJSON(fromConfigDirectory configDirectory: String) throws -> String {
        let normalizedConfigDir = normalizedConfigDirectory(configDirectory)
        guard let normalizedConfigDir else {
            throw ClaudeAccountProfileError.missingConfigDirectory
        }
        let path = credentialsFilePath(configDirectory: normalizedConfigDir)
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let text = String(data: data, encoding: .utf8) else {
            throw ClaudeAccountProfileError.missingCredentialsFile(path)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ClaudeAccountProfileError.missingCredentialsFile(path)
        }
        return trimmed
    }

    static func matchingIndex(
        for snapshot: UsageSnapshot,
        in profiles: [ClaudeAccountProfile]
    ) -> Int? {
        if let explicitSlot = ClaudeAccountSlotStore.explicitSlotID(from: snapshot),
           let index = profiles.firstIndex(where: { $0.slotID == explicitSlot }) {
            return index
        }

        let fingerprint = normalizedFingerprint(snapshot.rawMeta["claude.credentialFingerprint"])
        if let fingerprint {
            return profiles.firstIndex(where: { normalizedFingerprint($0.credentialFingerprint) == fingerprint })
        }

        let email = normalizedEmail(snapshot.accountLabel ?? snapshot.rawMeta["claude.accountLabel"])
        if let email,
           let index = profiles.firstIndex(where: { normalizedEmail($0.accountEmail) == email }) {
            return index
        }

        return nil
    }

    private static func resolveCredentialsJSON(
        source: ClaudeProfileSource,
        configDir: String?,
        credentialsJSON: String?
    ) throws -> String {
        let trimmedCredentials = credentialsJSON?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch source {
        case .configDir:
            guard let configDir else {
                throw ClaudeAccountProfileError.missingConfigDirectory
            }
            return try loadCredentialsJSON(fromConfigDirectory: configDir)
        case .manualCredentials:
            if let trimmedCredentials, !trimmedCredentials.isEmpty {
                return trimmedCredentials
            }
            if let configDir {
                return try loadCredentialsJSON(fromConfigDirectory: configDir)
            }
            throw ClaudeAccountProfileError.missingStoredCredentials
        }
    }

    private static func extractAccountEmail(from json: [String: Any], oauth: [String: Any]) -> String? {
        if let email = OfficialValueParser.string(json["email"]) {
            return email
        }
        if let user = json["user"] as? [String: Any],
           let email = OfficialValueParser.string(user["email"]) {
            return email
        }
        if let account = json["account"] as? [String: Any],
           let email = OfficialValueParser.string(account["email"]) {
            return email
        }
        if let oauthEmail = OfficialValueParser.string(oauth["email"]) {
            return oauthEmail
        }
        return nil
    }

    private static func fallbackDisplayName(_ displayName: String, slotID: CodexSlotID) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Claude \(slotID.rawValue)" : trimmed
    }

    private static func normalizedFingerprint(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }

    private static func normalizedEmail(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }

    private static func matchingIndex(
        for payload: ClaudeParsedCredentialsPayload,
        in profiles: [ClaudeAccountProfile]
    ) -> Int? {
        if let fingerprint = normalizedFingerprint(payload.credentialFingerprint) {
            return profiles.firstIndex(where: { normalizedFingerprint($0.credentialFingerprint) == fingerprint })
        }

        if let email = normalizedEmail(payload.accountEmail),
           let index = profiles.firstIndex(where: { normalizedEmail($0.accountEmail) == email }) {
            return index
        }

        return nil
    }

    private func normalizedProfile(_ profile: ClaudeAccountProfile) -> ClaudeAccountProfile {
        var updated = profile
        updated.configDir = Self.normalizedConfigDirectory(updated.configDir)
        updated.displayName = Self.fallbackDisplayName(updated.displayName, slotID: updated.slotID)
        if let credentialsJSON = updated.credentialsJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
           !credentialsJSON.isEmpty,
           let payload = try? Self.parseCredentialsJSON(credentialsJSON) {
            if updated.accountId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                updated.accountId = payload.accountId
            }
            if updated.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                updated.accountEmail = payload.accountEmail
            }
            if updated.credentialFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                updated.credentialFingerprint = payload.credentialFingerprint
            }
        }
        return updated
    }

    private func load() -> [ClaudeAccountProfile] {
        loadFile().profiles.map { normalizedProfile($0) }
    }

    private func loadIgnoredFingerprints() -> Set<String> {
        Set(loadFile().ignoredFingerprints?.map { $0.lowercased() } ?? [])
    }

    private func loadFile() -> ProfileFile {
        let directory = fileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: fileURL) else {
            return ProfileFile(profiles: [], ignoredFingerprints: [])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(ProfileFile.self, from: data) {
            return decoded
        }
        return ProfileFile(profiles: [], ignoredFingerprints: [])
    }

    private func save(_ profiles: [ClaudeAccountProfile], ignoredFingerprints: Set<String> = []) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(
            ProfileFile(
                profiles: profiles,
                ignoredFingerprints: ignoredFingerprints.isEmpty ? nil : ignoredFingerprints.sorted()
            )
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
