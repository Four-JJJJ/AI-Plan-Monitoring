import Foundation

enum ClaudeDesktopAuthError: LocalizedError {
    case invalidCredentials
    case noWritableCredentialPath
    case fileWriteFailed(String)
    case keychainWriteFailed

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid Claude credentials JSON"
        case .noWritableCredentialPath:
            return "Unable to locate a writable Claude credentials path"
        case .fileWriteFailed(let path):
            return "Failed to write Claude credentials at \(path)"
        case .keychainWriteFailed:
            return "Failed to update Claude Code keychain credentials"
        }
    }
}

final class ClaudeDesktopAuthService {
    private let fileManager: FileManager
    private let homeDirectory: () -> String
    private let environment: () -> [String: String]
    private let keychainReader: () -> String?
    private let keychainWriter: (String) -> Bool

    init(
        fileManager: FileManager = .default,
        homeDirectory: @escaping () -> String = { NSHomeDirectory() },
        environment: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment },
        keychainReader: @escaping () -> String? = {
            SecurityCredentialReader.readGenericPassword(service: "Claude Code-credentials")
        },
        keychainWriter: @escaping (String) -> Bool = { value in
            SecurityCredentialReader.saveGenericPassword(service: "Claude Code-credentials", text: value)
        }
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.keychainReader = keychainReader
        self.keychainWriter = keychainWriter
    }

    func resolvedConfigDirectories() -> [String] {
        let home = homeDirectory()
        let envConfigDir = ClaudeAccountProfileStore.normalizedConfigDirectory(environment()["CLAUDE_CONFIG_DIR"])
        let defaultDir = ClaudeAccountProfileStore.normalizedConfigDirectory("\(home)/.claude")
        let candidates = [envConfigDir, defaultDir].compactMap { $0 }
        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    func resolvedCredentialPaths() -> [String] {
        resolvedConfigDirectories().map { ClaudeAccountProfileStore.credentialsFilePath(configDirectory: $0) }
    }

    func currentSystemConfigDirectory() -> String? {
        resolvedConfigDirectories().first
    }

    func currentCredentialsJSON() -> String? {
        for path in resolvedCredentialPaths() where fileManager.fileExists(atPath: path) {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let text = String(data: data, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return keychainReader()
    }

    func currentCredentialFingerprint() -> String? {
        guard let raw = currentCredentialsJSON(),
              let payload = try? ClaudeAccountProfileStore.parseCredentialsJSON(raw) else {
            return nil
        }
        return payload.credentialFingerprint
    }

    func applyCredentialsJSON(_ credentialsJSON: String) throws {
        let trimmed = credentialsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              (try? ClaudeAccountProfileStore.parseCredentialsJSON(trimmed)) != nil else {
            throw ClaudeDesktopAuthError.invalidCredentials
        }

        let existingPaths = resolvedCredentialPaths().filter { fileManager.fileExists(atPath: $0) }
        let targets = existingPaths.isEmpty ? Array(resolvedCredentialPaths().prefix(1)) : existingPaths
        guard !targets.isEmpty else {
            throw ClaudeDesktopAuthError.noWritableCredentialPath
        }

        for path in targets {
            let url = URL(fileURLWithPath: path)
            do {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let data = trimmed.data(using: .utf8) else {
                    throw ClaudeDesktopAuthError.invalidCredentials
                }
                try data.write(to: url, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                throw ClaudeDesktopAuthError.fileWriteFailed(path)
            }
        }

        guard keychainWriter(trimmed) else {
            throw ClaudeDesktopAuthError.keychainWriteFailed
        }
    }
}
