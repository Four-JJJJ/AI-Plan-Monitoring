import Foundation

enum CodexDesktopAuthError: LocalizedError {
    case invalidProfile
    case noWritableAuthPath
    case fileWriteFailed(String)
    case keychainWriteFailed

    var errorDescription: String? {
        switch self {
        case .invalidProfile:
            return "Invalid Codex auth profile"
        case .noWritableAuthPath:
            return "Unable to locate a writable Codex auth.json path"
        case .fileWriteFailed(let path):
            return "Failed to write Codex auth.json at \(path)"
        case .keychainWriteFailed:
            return "Failed to update Codex Auth keychain entry"
        }
    }
}

final class CodexDesktopAuthService {
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
            SecurityCredentialReader.readGenericPassword(service: "Codex Auth")
        },
        keychainWriter: @escaping (String) -> Bool = { value in
            SecurityCredentialReader.saveGenericPassword(service: "Codex Auth", text: value)
        }
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.keychainReader = keychainReader
        self.keychainWriter = keychainWriter
    }

    func resolvedAuthPaths() -> [String] {
        CodexAuthPathResolver.resolveAuthPaths(
            homeDirectory: homeDirectory(),
            environment: environment()
        )
    }

    func currentAuthJSON() -> String? {
        for path in resolvedAuthPaths() where fileManager.fileExists(atPath: path) {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let text = String(data: data, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return keychainReader()
    }

    func currentCredentialFingerprint() -> String? {
        guard let raw = currentAuthJSON(),
              let payload = try? CodexAccountProfileStore.parseAuthJSON(raw) else {
            return nil
        }
        return payload.credentialFingerprint
    }

    func applyProfile(_ profile: CodexAccountProfile) throws {
        guard !profile.authJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (try? CodexAccountProfileStore.parseAuthJSON(profile.authJSON)) != nil else {
            throw CodexDesktopAuthError.invalidProfile
        }

        let existingPaths = resolvedAuthPaths().filter { fileManager.fileExists(atPath: $0) }
        let targets = existingPaths.isEmpty ? Array(resolvedAuthPaths().prefix(1)) : existingPaths
        guard !targets.isEmpty else {
            throw CodexDesktopAuthError.noWritableAuthPath
        }

        for path in targets {
            let url = URL(fileURLWithPath: path)
            do {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let data = profile.authJSON.data(using: .utf8) else {
                    throw CodexDesktopAuthError.invalidProfile
                }
                try data.write(to: url, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                throw CodexDesktopAuthError.fileWriteFailed(path)
            }
        }

        guard keychainWriter(profile.authJSON) else {
            throw CodexDesktopAuthError.keychainWriteFailed
        }
    }
}
