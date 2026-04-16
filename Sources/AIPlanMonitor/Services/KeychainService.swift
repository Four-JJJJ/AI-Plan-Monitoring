import Foundation
import LocalAuthentication
import Security

final class KeychainService {
    static let defaultServiceName = "AI Plan Monitor"
    static let legacyServiceName = "AIPlanMonitor"
    private static let vaultAccount = "__credential_vault__"
    private static let legacyMigrationDefaultsKey = "AIPlanMonitor.Keychain.LegacyMigrationComplete"
    private static let secureAccessPreparedDefaultsKey = "AIPlanMonitor.Keychain.SecureAccessPrepared"

    private let lock = NSLock()
    private let fileManager: FileManager
    private let storageURL: URL?
    private let useFileStorage: Bool
    private let defaults: UserDefaults
    private var tokenCache: [String: String] = [:]
    private var missingCache: Set<String> = []
    private var secureVaultLoaded = false

    init(
        fileManager: FileManager = .default,
        storageURL: URL? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.fileManager = fileManager
        self.storageURL = storageURL
        self.defaults = defaults
        self.useFileStorage = storageURL != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if useFileStorage {
            loadFromDisk()
        }
    }

    private func cacheKey(service: String, account: String) -> String {
        "\(normalizedServiceName(service))::\(account)"
    }

    func readToken(service: String, account: String) -> String? {
        let normalizedService = normalizedServiceName(service)
        let key = cacheKey(service: normalizedService, account: account)

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

        let token: String?
        if useFileStorage {
            token = readFromDisk(service: normalizedService, account: account)
        } else {
            guard hasPreparedSecureStoreAccess else {
                lock.lock()
                missingCache.insert(key)
                lock.unlock()
                return nil
            }
            token = readFromVault(service: normalizedService, account: account)
                ?? readCurrentServiceAndMigrateIfPossible(service: normalizedService, account: account)
        }

        lock.lock()
        if let token, !token.isEmpty {
            tokenCache[key] = token
            missingCache.remove(key)
        } else {
            missingCache.insert(key)
        }
        lock.unlock()
        return token
    }

    @discardableResult
    func saveToken(_ token: String, service: String, account: String) -> Bool {
        let normalizedService = normalizedServiceName(service)
        let key = cacheKey(service: normalizedService, account: account)

        lock.lock()
        tokenCache[key] = token
        missingCache.remove(key)
        let snapshot = tokenCache
        lock.unlock()

        if useFileStorage {
            return persist(snapshot)
        }

        let ok = persistSecureSnapshot(snapshot)
        if ok {
            defaults.set(true, forKey: Self.secureAccessPreparedDefaultsKey)
        }
        return ok
    }

    private var hasPreparedSecureStoreAccess: Bool {
        useFileStorage || defaults.bool(forKey: Self.secureAccessPreparedDefaultsKey)
    }

    private func normalizedServiceName(_ service: String) -> String {
        let trimmed = service.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == Self.legacyServiceName {
            return Self.defaultServiceName
        }
        return trimmed
    }

    private func readFromVault(service: String, account: String) -> String? {
        loadSecureVaultIfNeeded(interactive: false)

        let key = cacheKey(service: service, account: account)
        lock.lock()
        defer { lock.unlock() }
        return tokenCache[key]
    }

    private func readCurrentServiceAndMigrateIfPossible(service: String, account: String) -> String? {
        guard service != Self.defaultServiceName || account != Self.vaultAccount,
              let token = readFromSecureStore(service: service, account: account, interactive: false),
              !token.isEmpty else {
            return nil
        }

        _ = storeInVault(token: token, service: service, account: account)
        return token
    }

    private func loadSecureVaultIfNeeded(interactive: Bool) {
        lock.lock()
        if secureVaultLoaded {
            lock.unlock()
            return
        }
        secureVaultLoaded = true
        lock.unlock()

        if let snapshot = readVaultSnapshotFromSecureStore(interactive: interactive), !snapshot.isEmpty {
            mergeIntoCache(snapshot)
        }

        if let currentItems = readAllFromSecureStore(service: Self.defaultServiceName, interactive: interactive)?
            .filter({ $0.key != Self.vaultAccount && !$0.key.isEmpty && !$0.value.isEmpty }),
           !currentItems.isEmpty {
            let normalized = currentItems.reduce(into: [String: String]()) { partialResult, entry in
                partialResult[cacheKey(service: Self.defaultServiceName, account: entry.key)] = entry.value
            }
            _ = mergeIntoVault(normalized)
        }
    }

    func prepareSecureStoreAccess() -> Bool {
        loadSecureVaultIfNeeded(interactive: true)
        migrateLegacyServiceOnceIfNeeded(interactive: true)
        if readVaultSnapshotFromSecureStore(interactive: true) != nil {
            defaults.set(true, forKey: Self.secureAccessPreparedDefaultsKey)
            return true
        }
        let ok = persistSecureSnapshot(tokenCache)
        if ok {
            defaults.set(true, forKey: Self.secureAccessPreparedDefaultsKey)
        }
        return ok
    }

    func isSecureStoreReady() -> Bool {
        guard !useFileStorage else {
            return true
        }
        guard hasPreparedSecureStoreAccess else {
            return false
        }
        loadSecureVaultIfNeeded(interactive: false)
        return readVaultSnapshotFromSecureStore(interactive: false) != nil
    }

    func resetAllStoredCredentials() {
        guard !useFileStorage else {
            lock.lock()
            tokenCache.removeAll()
            missingCache.removeAll()
            secureVaultLoaded = false
            lock.unlock()
            if let storageURL {
                try? fileManager.removeItem(at: storageURL)
            }
            return
        }

        deleteAllSecureStoreItems(service: Self.defaultServiceName)
        deleteAllSecureStoreItems(service: Self.legacyServiceName)
        defaults.removeObject(forKey: Self.legacyMigrationDefaultsKey)
        defaults.removeObject(forKey: Self.secureAccessPreparedDefaultsKey)

        lock.lock()
        tokenCache.removeAll()
        missingCache.removeAll()
        secureVaultLoaded = false
        lock.unlock()
    }

    private func migrateLegacyServiceOnceIfNeeded(interactive: Bool) {
        guard !defaults.bool(forKey: Self.legacyMigrationDefaultsKey) else {
            return
        }

        guard let legacyItems = readAllFromSecureStore(service: Self.legacyServiceName, interactive: interactive)?
            .filter({ !$0.key.isEmpty && !$0.value.isEmpty }),
           !legacyItems.isEmpty else {
            if interactive {
                defaults.set(true, forKey: Self.legacyMigrationDefaultsKey)
            }
            return
        }

        let normalized = legacyItems.reduce(into: [String: String]()) { partialResult, entry in
            partialResult[cacheKey(service: Self.defaultServiceName, account: entry.key)] = entry.value
        }

        guard mergeIntoVault(normalized) else { return }

        for account in legacyItems.keys {
            deleteSecureStoreItem(service: Self.legacyServiceName, account: account)
        }
        defaults.set(true, forKey: Self.legacyMigrationDefaultsKey)
    }

    private func mergeIntoVault(_ items: [String: String]) -> Bool {
        guard !items.isEmpty else { return true }

        lock.lock()
        var merged = tokenCache
        for (key, value) in items where !value.isEmpty {
            merged[key] = value
        }
        lock.unlock()

        guard persistSecureSnapshot(merged) else {
            return false
        }

        mergeIntoCache(items)
        return true
    }

    private func storeInVault(token: String, service: String, account: String) -> Bool {
        mergeIntoVault([cacheKey(service: service, account: account): token])
    }

    private func mergeIntoCache(_ items: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        for (key, value) in items where !value.isEmpty {
            tokenCache[key] = value
            missingCache.remove(key)
        }
    }

    private func readVaultSnapshotFromSecureStore(interactive: Bool) -> [String: String]? {
        guard let data = readDataFromSecureStore(
            service: Self.defaultServiceName,
            account: Self.vaultAccount,
            interactive: interactive
        ) else {
            return nil
        }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    private func persistSecureSnapshot(_ snapshot: [String: String]) -> Bool {
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(snapshot)
        } catch {
            return false
        }
        return saveDataToSecureStore(encoded, service: Self.defaultServiceName, account: Self.vaultAccount)
    }

    private func readFromSecureStore(service: String, account: String, interactive: Bool) -> String? {
        guard let data = readDataFromSecureStore(service: service, account: account, interactive: interactive),
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    private func readDataFromSecureStore(service: String, account: String, interactive: Bool) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: authenticationContext(interactive: interactive)
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              !data.isEmpty else {
            return nil
        }
        return data
    }

    private func readAllFromSecureStore(service: String, interactive: Bool) -> [String: String]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseAuthenticationContext as String: authenticationContext(interactive: interactive)
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            return nil
        }

        let rows: [[String: Any]]
        if let array = item as? [[String: Any]] {
            rows = array
        } else if let dict = item as? [String: Any] {
            rows = [dict]
        } else {
            return nil
        }

        var result: [String: String] = [:]
        for row in rows {
            guard let account = row[kSecAttrAccount as String] as? String,
                  let data = row[kSecValueData as String] as? Data,
                  let token = String(data: data, encoding: .utf8),
                  !token.isEmpty else {
                continue
            }
            result[account] = token
        }
        return result
    }

    private func saveDataToSecureStore(_ data: Data, service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus != errSecItemNotFound {
            SecItemDelete(query as CFDictionary)
        }

        let addAttributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let addStatus = SecItemAdd(addAttributes as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    private func deleteSecureStoreItem(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func deleteAllSecureStoreItems(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func authenticationContext(interactive: Bool) -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = !interactive
        return context
    }

    private func readFromDisk(service: String, account: String) -> String? {
        tokenCache["\(service)::\(account)"]
    }

    private func loadFromDisk() {
        guard let storageURL,
              fileManager.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }

        lock.lock()
        tokenCache = decoded
        missingCache.removeAll()
        lock.unlock()
    }

    private func persist(_ snapshot: [String: String]) -> Bool {
        guard let storageURL else { return false }
        do {
            try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
