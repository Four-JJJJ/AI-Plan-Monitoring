import CryptoKit
import Foundation

enum CodexAccountProfileError: LocalizedError {
    case invalidJSON
    case missingAccessToken

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Invalid auth.json content"
        case .missingAccessToken:
            return "auth.json is missing access_token"
        }
    }
}

struct CodexParsedAuthPayload {
    var accessToken: String
    var refreshToken: String?
    var accountId: String?
    var idToken: String?
    var accountEmail: String?
    var credentialFingerprint: String
}

final class CodexAccountProfileStore {
    private struct ProfileFile: Codable {
        var profiles: [CodexAccountProfile]
    }

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directory = appSupport.appendingPathComponent("AIBalanceMonitor", isDirectory: true)
            self.fileURL = directory.appendingPathComponent("codex_profiles.json")
        }
    }

    func profiles() -> [CodexAccountProfile] {
        load().sorted { $0.slotID < $1.slotID }
    }

    func profile(slotID: CodexSlotID) -> CodexAccountProfile? {
        load().first(where: { $0.slotID == slotID })
    }

    @discardableResult
    func saveProfile(
        slotID: CodexSlotID,
        displayName: String,
        authJSON: String,
        currentFingerprint: String?
    ) throws -> CodexAccountProfile {
        var items = load()
        var profile = try Self.makeProfile(slotID: slotID, displayName: displayName, authJSON: authJSON)
        profile.isCurrentSystemAccount = profile.credentialFingerprint == currentFingerprint

        if let existing = items.firstIndex(where: { $0.slotID == slotID }) {
            items[existing] = profile
        } else {
            items.append(profile)
        }
        try save(items)
        return profile
    }

    @discardableResult
    func updateCurrentFingerprint(_ fingerprint: String?) -> [CodexAccountProfile] {
        var items = load()
        var changed = false
        for index in items.indices {
            let isCurrent = items[index].credentialFingerprint == fingerprint && fingerprint != nil
            if items[index].isCurrentSystemAccount != isCurrent {
                items[index].isCurrentSystemAccount = isCurrent
                changed = true
            }
        }
        if changed {
            try? save(items)
        }
        return items.sorted { $0.slotID < $1.slotID }
    }

    func nextAvailableSlotID() -> CodexSlotID {
        let existing = Set(load().map(\.slotID))
        return CodexSlotID.nextAvailable(excluding: existing)
    }

    @discardableResult
    func removeProfile(slotID: CodexSlotID) -> [CodexAccountProfile] {
        var items = load()
        guard items.first(where: { $0.slotID == slotID })?.isCurrentSystemAccount != true else {
            return items.sorted { $0.slotID < $1.slotID }
        }
        items.removeAll { $0.slotID == slotID }
        try? save(items)
        return items.sorted { $0.slotID < $1.slotID }
    }

    @discardableResult
    func captureCurrentAuthIfNeeded(
        authJSON: String?,
        preferredAutoSlots: [CodexSlotID] = [.a, .b]
    ) -> [CodexAccountProfile] {
        guard let authJSON else {
            return updateCurrentProfiles([], currentFingerprint: nil)
        }

        let trimmed = authJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let payload = try? Self.parseAuthJSON(trimmed) else {
            return updateCurrentProfiles([], currentFingerprint: nil)
        }

        var items = load()
        let currentFingerprint = payload.credentialFingerprint.lowercased()

        if let existing = matchingIndex(for: payload, in: items) {
            let previous = items[existing]
            var updated = previous
            updated.authJSON = trimmed
            updated.accountId = payload.accountId
            updated.accountEmail = payload.accountEmail
            updated.credentialFingerprint = payload.credentialFingerprint
            if previous.authJSON.trimmingCharacters(in: .whitespacesAndNewlines) != trimmed
                || previous.accountId != payload.accountId
                || previous.accountEmail != payload.accountEmail
                || previous.credentialFingerprint?.lowercased() != currentFingerprint {
                updated.lastImportedAt = Date()
            }
            items[existing] = updated
            return updateCurrentProfiles(items, currentFingerprint: currentFingerprint)
        }

        let occupied = Set(items.map(\.slotID))
        let slotID = preferredAutoSlots.first(where: { !occupied.contains($0) })
            ?? CodexSlotID.nextAvailable(excluding: occupied)

        items.append(
            CodexAccountProfile(
                slotID: slotID,
                displayName: "Codex \(slotID.rawValue)",
                authJSON: trimmed,
                accountId: payload.accountId,
                accountEmail: payload.accountEmail,
                credentialFingerprint: payload.credentialFingerprint,
                lastImportedAt: Date(),
                isCurrentSystemAccount: true
            )
        )

        return updateCurrentProfiles(items, currentFingerprint: currentFingerprint)
    }

    static func makeProfile(
        slotID: CodexSlotID,
        displayName: String,
        authJSON: String,
        importedAt: Date = Date()
    ) throws -> CodexAccountProfile {
        let payload = try parseAuthJSON(authJSON)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return CodexAccountProfile(
            slotID: slotID,
            displayName: trimmedName.isEmpty ? "Codex \(slotID.rawValue)" : trimmedName,
            authJSON: authJSON.trimmingCharacters(in: .whitespacesAndNewlines),
            accountId: payload.accountId,
            accountEmail: payload.accountEmail,
            credentialFingerprint: payload.credentialFingerprint,
            lastImportedAt: importedAt,
            isCurrentSystemAccount: false
        )
    }

    static func parseAuthJSON(_ raw: String) throws -> CodexParsedAuthPayload {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexAccountProfileError.invalidJSON
        }

        let tokens = (json["tokens"] as? [String: Any]) ?? json
        guard let accessToken = OfficialValueParser.string(tokens["access_token"] ?? tokens["accessToken"]),
              !accessToken.isEmpty else {
            throw CodexAccountProfileError.missingAccessToken
        }

        let accountId = OfficialValueParser.string(tokens["account_id"] ?? tokens["accountId"])
        let refreshToken = OfficialValueParser.string(tokens["refresh_token"] ?? tokens["refreshToken"])
        let idToken = OfficialValueParser.string(tokens["id_token"] ?? tokens["idToken"])
        let email = idToken.flatMap(decodeEmailFromJWT)
        let fingerprint = credentialFingerprint(for: accessToken) ?? credentialFingerprint(for: trimmed) ?? UUID().uuidString

        return CodexParsedAuthPayload(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountId: accountId,
            idToken: idToken,
            accountEmail: email,
            credentialFingerprint: fingerprint
        )
    }

    static func credentialFingerprint(for raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func decodeEmailFromJWT(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return OfficialValueParser.string(json["email"])
    }

    private func load() -> [CodexAccountProfile] {
        let directory = fileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(ProfileFile.self, from: data) {
            return decoded.profiles
        }
        return []
    }

    private func save(_ profiles: [CodexAccountProfile]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(ProfileFile(profiles: profiles))
        try data.write(to: fileURL, options: .atomic)
    }

    private func matchingIndex(
        for payload: CodexParsedAuthPayload,
        in profiles: [CodexAccountProfile]
    ) -> Int? {
        let fingerprint = payload.credentialFingerprint.lowercased()
        if let index = profiles.firstIndex(where: { $0.credentialFingerprint?.lowercased() == fingerprint }) {
            return index
        }

        if let accountId = payload.accountId?.lowercased(),
           let index = profiles.firstIndex(where: { $0.accountId?.lowercased() == accountId }) {
            return index
        }

        if let email = payload.accountEmail?.lowercased(),
           let index = profiles.firstIndex(where: { $0.accountEmail?.lowercased() == email }) {
            return index
        }

        return nil
    }

    private func updateCurrentProfiles(
        _ profiles: [CodexAccountProfile],
        currentFingerprint: String?
    ) -> [CodexAccountProfile] {
        var items = profiles
        var changed = false
        for index in items.indices {
            let isCurrent = items[index].credentialFingerprint?.lowercased() == currentFingerprint && currentFingerprint != nil
            if items[index].isCurrentSystemAccount != isCurrent {
                items[index].isCurrentSystemAccount = isCurrent
                changed = true
            }
        }
        if changed || profiles != load() {
            try? save(items)
        }
        return items.sorted { $0.slotID < $1.slotID }
    }
}
