import Foundation
import LocalAuthentication
import Security

final class KeychainService {
    private let lock = NSLock()
    private var tokenCache: [String: String] = [:]
    private var missingCache: Set<String> = []
    private var diskTokens: [String: String] = [:]
    private var diskLoaded = false
    private let tokensFileURL: URL

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("AIBalanceMonitor", isDirectory: true)
        self.tokensFileURL = directory.appendingPathComponent("tokens.json")
    }

    private func cacheKey(service: String, account: String) -> String {
        "\(service)::\(account)"
    }

    func readToken(service: String, account: String) -> String? {
        let key = cacheKey(service: service, account: account)

        lock.lock()
        if let cached = tokenCache[key] {
            lock.unlock()
            return cached
        }
        if missingCache.contains(key) {
            lock.unlock()
            return nil
        }
        lock.unlock()

        if let token = readDiskToken(for: key) {
            lock.lock()
            tokenCache[key] = token
            missingCache.remove(key)
            lock.unlock()
            return token
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: nonInteractiveContext()
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            lock.lock()
            missingCache.insert(key)
            lock.unlock()
            return nil
        }

        lock.lock()
        tokenCache[key] = token
        missingCache.remove(key)
        lock.unlock()

        _ = writeDiskToken(token, for: key)
        return token
    }

    @discardableResult
    func saveToken(_ token: String, service: String, account: String) -> Bool {
        let key = cacheKey(service: service, account: account)
        let diskSaved = writeDiskToken(token, for: key)

        lock.lock()
        tokenCache[key] = token
        missingCache.remove(key)
        lock.unlock()

        let data = token.data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: nonInteractiveContext()
        ]

        SecItemDelete(query as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecUseAuthenticationContext as String: nonInteractiveContext()
        ]

        _ = SecItemAdd(attributes as CFDictionary, nil)
        return diskSaved
    }

    private func readDiskToken(for key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        loadDiskTokensIfNeededLocked()
        return diskTokens[key]
    }

    @discardableResult
    private func writeDiskToken(_ token: String, for key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        loadDiskTokensIfNeededLocked()
        diskTokens[key] = token
        return persistDiskTokensLocked()
    }

    private func loadDiskTokensIfNeededLocked() {
        guard !diskLoaded else { return }
        diskLoaded = true
        guard let data = try? Data(contentsOf: tokensFileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            diskTokens = [:]
            return
        }
        diskTokens = decoded
    }

    @discardableResult
    private func persistDiskTokensLocked() -> Bool {
        let directory = tokensFileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(diskTokens)
            try data.write(to: tokensFileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokensFileURL.path)
            return true
        } catch {
            return false
        }
    }

    private func nonInteractiveContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }
}
