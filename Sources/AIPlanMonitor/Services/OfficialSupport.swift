import Foundation
import CommonCrypto
import LocalAuthentication
import Security
import Darwin

struct BrowserCookieHeader: Equatable {
    let header: String
    let source: String
}

protocol BrowserCookieDetecting {
    func detectCookieHeader(hostContains: String, order: [KimiBrowserKind]?) -> BrowserCookieHeader?
    func detectNamedCookie(name: String, hostContains: String, order: [KimiBrowserKind]?) -> BrowserCookieHeader?
}

struct ShellCommand {
    static func run(
        executable: String,
        arguments: [String],
        input: String? = nil,
        timeout: TimeInterval = 20,
        environment: [String: String]? = nil,
        currentDirectory: String? = nil
    ) -> (status: Int32, stdout: String, stderr: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory, isDirectory: true)
        }

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        let inputPipe = Pipe()
        if input != nil {
            process.standardInput = inputPipe
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        if let input {
            if let data = input.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            try? inputPipe.fileHandleForWriting.close()
        }

        var didTimeout = false
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            didTimeout = true
            if process.isRunning {
                process.terminate()
                if finished.wait(timeout: .now() + 1.0) == .timedOut, process.isRunning {
                    // SIGTERM 无效时强制杀进程，避免 Process 仍在运行导致崩溃。
                    kill(process.processIdentifier, SIGKILL)
                    _ = finished.wait(timeout: .now() + 1.0)
                }
            }
        }

        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.isRunning {
            // 极端情况下仍未退出，返回超时状态并避免触发 terminationStatus 异常。
            kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 1.0)
            return (didTimeout ? 124 : -1, stdout, stderr)
        }

        return (process.terminationStatus, stdout, stderr)
    }
}

enum SecurityCredentialReader {
    private struct CredentialCacheKey: Hashable {
        let service: String
        let account: String?
    }

    private enum CachedCredentialValue {
        case value(String)
        case missing
    }

    private struct CachedCredential {
        let value: CachedCredentialValue
        let expiresAt: Date
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var credentialCache: [CredentialCacheKey: CachedCredential] = [:]
    private static let successCacheTTL: TimeInterval = 120
    private static let failureBackoffInterval: TimeInterval = 8

    static func readGenericPassword(service: String, account: String? = nil, bypassCache: Bool = false) -> String? {
        let normalizedService = normalize(service)
        let normalizedAccount = normalizeOptional(account)
        let cacheKey = CredentialCacheKey(service: normalizedService, account: normalizedAccount)
        let now = Date()

        if !bypassCache, let cached = cachedCredential(for: cacheKey, now: now) {
            switch cached {
            case .value(let value):
                return value
            case .missing:
                return nil
            }
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: normalizedService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: nonInteractiveContext(),
        ]
        if let normalizedAccount {
            query[kSecAttrAccount as String] = normalizedAccount
        } else if let account {
            query[kSecAttrAccount as String] = account
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let text = String(data: data, encoding: .utf8),
           !text.isEmpty {
            cache(.value(text), for: cacheKey, now: now)
            return text
        }
        cache(.missing, for: cacheKey, now: now)
        return nil
    }

    @discardableResult
    static func saveGenericPassword(service: String, account: String? = nil, text: String) -> Bool {
        let normalizedService = normalize(service)
        let normalizedAccount = normalizeOptional(account) ?? normalizedService
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: normalizedService,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let data = Data(text.utf8)
        let addAttributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: normalizedService,
            kSecAttrAccount as String: normalizedAccount,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(addAttributes as CFDictionary, nil)
        if status == errSecSuccess {
            let now = Date()
            cache(.value(text), for: CredentialCacheKey(service: normalizedService, account: normalizedAccount), now: now)
            cache(.value(text), for: CredentialCacheKey(service: normalizedService, account: nil), now: now)
            return true
        }

        let args = [
            "add-generic-password",
            "-U",
            "-s", normalizedService,
            "-a", normalizedAccount,
            "-w", text
        ]
        guard let output = ShellCommand.run(executable: "/usr/bin/security", arguments: args, timeout: 5) else {
            return false
        }
        if output.status == 0 {
            let now = Date()
            cache(.value(text), for: CredentialCacheKey(service: normalizedService, account: normalizedAccount), now: now)
            cache(.value(text), for: CredentialCacheKey(service: normalizedService, account: nil), now: now)
            return true
        }
        return false
    }

    private static func cachedCredential(for key: CredentialCacheKey, now: Date) -> CachedCredentialValue? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        purgeExpiredEntriesLocked(now: now)
        guard let entry = credentialCache[key] else {
            return nil
        }
        return entry.value
    }

    private static func cache(_ value: CachedCredentialValue, for key: CredentialCacheKey, now: Date) {
        let ttl: TimeInterval
        switch value {
        case .value:
            ttl = successCacheTTL
        case .missing:
            ttl = failureBackoffInterval
        }

        cacheLock.lock()
        credentialCache[key] = CachedCredential(
            value: value,
            expiresAt: now.addingTimeInterval(max(0, ttl))
        )
        purgeExpiredEntriesLocked(now: now)
        cacheLock.unlock()
    }

    private static func purgeExpiredEntriesLocked(now: Date) {
        credentialCache = credentialCache.filter { _, value in
            value.expiresAt > now
        }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nonInteractiveContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }
}

enum OfficialValueParser {
    private static let placeholderValues: Set<String> = [
        "-", "--", "unknown", "undefined", "null", "nil", "none", "n/a", "na", "(null)", "(unknown)"
    ]

    static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    static func string(_ value: Any?) -> String? {
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    static func nonPlaceholderString(_ value: Any?) -> String? {
        guard let text = string(value) else { return nil }
        return placeholderValues.contains(text.lowercased()) ? nil : text
    }

    static func isoDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        return fallback.date(from: raw)
    }

    static func httpDate(_ raw: String?) -> Date? {
        guard let raw = string(raw) else { return nil }
        for format in [
            "EEE',' dd MMM yyyy HH':'mm':'ss zzz", // RFC 1123
            "EEEE',' dd-MMM-yy HH':'mm':'ss zzz", // RFC 850
            "EEE MMM d HH':'mm':'ss yyyy" // ANSI C asctime
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let parsed = formatter.date(from: raw) {
                return parsed
            }
        }
        return nil
    }

    static func responseServerDate(_ response: HTTPURLResponse) -> Date? {
        httpDate(response.value(forHTTPHeaderField: "Date"))
    }

    static func clockSkew(response: HTTPURLResponse, localReceiveAt: Date = Date()) -> TimeInterval? {
        guard let serverNow = responseServerDate(response) else { return nil }
        return localReceiveAt.timeIntervalSince(serverNow)
    }

    static func applyClockSkew(_ date: Date?, skew: TimeInterval?) -> Date? {
        guard let date else { return nil }
        guard let skew else { return date }
        return date.addingTimeInterval(skew)
    }

    static func epochDate(seconds: Any?) -> Date? {
        if let number = double(seconds) {
            return Date(timeIntervalSince1970: number)
        }
        return nil
    }
}

enum LocalJSONFileReader {
    static func dictionary(atPath path: String) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    static func text(atPath path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
}

enum JWTInspector {
    static func payload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    static func email(_ token: String) -> String? {
        OfficialValueParser.string(payload(token)?["email"])
    }

    static func subject(_ token: String) -> String? {
        OfficialValueParser.string(payload(token)?["sub"])
    }

    static func expirationDate(_ token: String) -> Date? {
        guard let exp = OfficialValueParser.double(payload(token)?["exp"]) else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}

enum SQLiteShell {
    static func rows(databasePath: String, query: String, separator: String = "\t") -> [[String]] {
        guard FileManager.default.fileExists(atPath: databasePath),
              let result = ShellCommand.run(
                executable: "/usr/bin/sqlite3",
                arguments: ["-separator", separator, databasePath, query],
                timeout: 10
              ),
              result.status == 0 else {
            return []
        }
        return result.stdout
            .split(separator: "\n")
            .map { line in line.components(separatedBy: separator) }
    }

    static func singleValue(databasePath: String, query: String) -> String? {
        rows(databasePath: databasePath, query: query, separator: "\t")
            .first?.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    static func execute(databasePath: String, sql: String) -> Bool {
        guard FileManager.default.fileExists(atPath: databasePath),
              let result = ShellCommand.run(
                executable: "/usr/bin/sqlite3",
                arguments: [databasePath, sql],
                timeout: 10
              ) else {
            return false
        }
        return result.status == 0
    }
}

final class BrowserCookieService: BrowserCookieDetecting {
    private let fileManager: FileManager
    private let browserOrderDefault: [KimiBrowserKind] = [.arc, .chrome, .safari, .edge, .brave, .firefox, .opera, .operaGX, .vivaldi, .chromium]
    private var safeStorageCache: [KimiBrowserKind: String] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func detectCookieHeader(hostContains: String, order: [KimiBrowserKind]? = nil) -> BrowserCookieHeader? {
        let actualOrder = order ?? browserOrderDefault
        for browser in actualOrder {
            for path in candidateCookiePaths(for: browser) {
                if let header = cookieHeaderFromCookieDatabase(path: path, browser: browser, hostContains: hostContains),
                   !header.isEmpty {
                    return BrowserCookieHeader(header: header, source: browserLabel(browser))
                }
            }
        }
        return nil
    }

    func detectNamedCookie(name: String, hostContains: String, order: [KimiBrowserKind]? = nil) -> BrowserCookieHeader? {
        let actualOrder = order ?? browserOrderDefault
        for browser in actualOrder {
            for path in candidateCookiePaths(for: browser) {
                if let value = tokenFromCookieDatabase(path: path, browser: browser, cookieName: name, hostContains: hostContains),
                   !value.isEmpty {
                    return BrowserCookieHeader(header: "\(name)=\(value)", source: browserLabel(browser))
                }
            }
        }
        return nil
    }

    private func candidateCookiePaths(for browser: KimiBrowserKind) -> [String] {
        let home = NSHomeDirectory()
        switch browser {
        case .arc:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/Arc/User Data")
        case .chrome:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/Google/Chrome")
        case .safari:
            return [
                "\(home)/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData/Default/Cookies/Cookies.sqlite",
                "\(home)/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.sqlite",
                "\(home)/Library/Cookies/Cookies.binarycookies",
            ]
        case .edge:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/Microsoft Edge")
        case .brave:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/BraveSoftware/Brave-Browser")
        case .chromium:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/Chromium")
        case .firefox:
            return firefoxCookiePaths(base: "\(home)/Library/Application Support/Firefox")
        case .opera:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/com.operasoftware.Opera")
        case .operaGX:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/com.operasoftware.OperaGX")
        case .vivaldi:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/Vivaldi")
        }
    }

    private func chromiumCookiePaths(base: String) -> [String] {
        guard fileManager.fileExists(atPath: base) else { return [] }
        var candidates: [String] = []
        let baseURL = URL(fileURLWithPath: base)
        let keys: [URLResourceKey] = [.isDirectoryKey]
        if let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: keys) {
            for case let url as URL in enumerator {
                let path = url.path
                if path.hasSuffix("/Cookies") &&
                    (path.contains("/Network/") || path.contains("/Default/") || path.contains("/Profile ")) {
                    candidates.append(path)
                }
            }
        }
        return Array(Set(candidates)).sorted()
    }

    private func firefoxCookiePaths(base: String) -> [String] {
        guard fileManager.fileExists(atPath: base) else { return [] }
        var candidates: [String] = []
        let baseURL = URL(fileURLWithPath: base)
        let keys: [URLResourceKey] = [.isDirectoryKey]
        if let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: keys) {
            for case let url as URL in enumerator where url.lastPathComponent == "cookies.sqlite" {
                candidates.append(url.path)
            }
        }
        return Array(Set(candidates)).sorted()
    }

    private func tokenFromCookieDatabase(path: String, browser: KimiBrowserKind, cookieName: String, hostContains: String) -> String? {
        guard fileManager.fileExists(atPath: path) else { return nil }
        guard let sqlite = resolvedSQLitePath() else { return nil }

        let tempDB = "\(NSTemporaryDirectory())/official_cookie_\(UUID().uuidString).sqlite"
        defer { try? fileManager.removeItem(atPath: tempDB) }

        do {
            try fileManager.copyItem(atPath: path, toPath: tempDB)
        } catch {
            return nil
        }

        let queries = [
            // Chromium / WebKit (encrypted cookies)
            "SELECT value, hex(encrypted_value) FROM cookies WHERE name='\(cookieName)' AND host_key LIKE '%\(hostContains)%' ORDER BY LENGTH(value) DESC, LENGTH(encrypted_value) DESC;",
            "SELECT value, hex(encrypted_value) FROM cookies WHERE name='\(cookieName)' AND domain LIKE '%\(hostContains)%' ORDER BY LENGTH(value) DESC, LENGTH(encrypted_value) DESC;",
            "SELECT value, hex(encrypted_value) FROM Cookies WHERE name='\(cookieName)' AND host LIKE '%\(hostContains)%' ORDER BY LENGTH(value) DESC, LENGTH(encrypted_value) DESC;",
            "SELECT value, hex(encrypted_value) FROM Cookies WHERE name='\(cookieName)' AND domain LIKE '%\(hostContains)%' ORDER BY LENGTH(value) DESC, LENGTH(encrypted_value) DESC;",
            // Firefox / plain sqlite schema
            "SELECT value, '' FROM moz_cookies WHERE name='\(cookieName)' AND host LIKE '%\(hostContains)%' ORDER BY LENGTH(value) DESC;",
            "SELECT value, '' FROM cookies WHERE name='\(cookieName)' AND host LIKE '%\(hostContains)%' ORDER BY LENGTH(value) DESC;",
        ]

        for query in queries {
            guard let raw = ShellCommand.run(executable: sqlite, arguments: ["-separator", "\t", tempDB, query], timeout: 5)?.stdout else {
                continue
            }
            for lineSub in raw.split(separator: "\n") {
                let line = String(lineSub)
                let parts = line.components(separatedBy: "\t")
                let plain = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let encryptedHex = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                let selected: String
                if !plain.isEmpty {
                    selected = plain
                } else if let decrypted = decryptChromiumCookieHex(encryptedHex, browser: browser), !decrypted.isEmpty {
                    selected = decrypted
                } else {
                    continue
                }

                let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
                if let decoded = trimmed.removingPercentEncoding, !decoded.isEmpty {
                    return decoded
                }
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return nil
    }

    private func cookieHeaderFromCookieDatabase(path: String, browser: KimiBrowserKind, hostContains: String) -> String? {
        guard fileManager.fileExists(atPath: path) else { return nil }
        guard let sqlite = resolvedSQLitePath() else { return nil }

        let tempDB = "\(NSTemporaryDirectory())/official_cookie_header_\(UUID().uuidString).sqlite"
        defer { try? fileManager.removeItem(atPath: tempDB) }
        do {
            try fileManager.copyItem(atPath: path, toPath: tempDB)
        } catch {
            return nil
        }

        let queries = [
            // Chromium / WebKit (encrypted cookies)
            "SELECT name, value, hex(encrypted_value) FROM cookies WHERE host_key LIKE '%\(hostContains)%' ORDER BY name;",
            "SELECT name, value, hex(encrypted_value) FROM cookies WHERE domain LIKE '%\(hostContains)%' ORDER BY name;",
            "SELECT name, value, hex(encrypted_value) FROM Cookies WHERE host LIKE '%\(hostContains)%' ORDER BY name;",
            "SELECT name, value, hex(encrypted_value) FROM Cookies WHERE domain LIKE '%\(hostContains)%' ORDER BY name;",
            // Firefox / plain sqlite schema
            "SELECT name, value, '' FROM moz_cookies WHERE host LIKE '%\(hostContains)%' ORDER BY name;",
            "SELECT name, value, '' FROM cookies WHERE host LIKE '%\(hostContains)%' ORDER BY name;",
        ]
        for query in queries {
            guard let raw = ShellCommand.run(executable: sqlite, arguments: ["-separator", "\t", tempDB, query], timeout: 5)?.stdout else {
                continue
            }
            var pairs: [String] = []
            for lineSub in raw.split(separator: "\n") {
                let line = String(lineSub)
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 3 else { continue }
                let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let plain = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let encryptedHex = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                let value: String
                if !plain.isEmpty {
                    value = plain
                } else if let decrypted = decryptChromiumCookieHex(encryptedHex, browser: browser), !decrypted.isEmpty {
                    value = decrypted
                } else {
                    continue
                }
                pairs.append("\(name)=\(value)")
            }
            if !pairs.isEmpty {
                return pairs.joined(separator: "; ")
            }
        }

        return nil
    }

    private func decryptChromiumCookieHex(_ hex: String, browser: KimiBrowserKind) -> String? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let encrypted = HexDataParser.data(from: cleaned),
              encrypted.count > 3 else {
            return nil
        }

        let versionPrefix = encrypted.prefix(3)
        guard versionPrefix == Data([0x76, 0x31, 0x30]) || versionPrefix == Data([0x76, 0x31, 0x31]) else {
            return nil
        }

        guard let passphrase = safeStoragePassword(for: browser), !passphrase.isEmpty,
              let key = pbkdf2SHA1(password: passphrase, salt: "saltysalt", rounds: 1003, keyByteCount: 16) else {
            return nil
        }

        let cipher = Data(encrypted.dropFirst(3))
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        guard let decrypted = aesCBCDecrypt(ciphertext: cipher, key: key, iv: iv) else {
            return nil
        }

        if let decoded = String(data: decrypted, encoding: .utf8), !decoded.isEmpty {
            return cleanCookieValue(decoded)
        }

        if decrypted.count > 32 {
            let trimmed = Data(decrypted.dropFirst(32))
            if let decoded = String(data: trimmed, encoding: .utf8), !decoded.isEmpty {
                return cleanCookieValue(decoded)
            }
        }

        return nil
    }

    private func safeStoragePassword(for browser: KimiBrowserKind) -> String? {
        if let cached = safeStorageCache[browser] {
            return cached
        }

        let labels = safeStorageLabels(for: browser)
        for label in labels {
            if let password = SecurityCredentialReader.readGenericPassword(service: label.service, account: label.account), !password.isEmpty {
                safeStorageCache[browser] = password
                return password
            }
        }

        return nil
    }

    private func safeStorageLabels(for browser: KimiBrowserKind) -> [(service: String, account: String)] {
        switch browser {
        case .arc:
            return [
                ("Arc Safe Storage", "Arc"),
                ("Arc Safe Storage", "Arc Beta"),
                ("Arc Safe Storage", "Arc Canary"),
                ("Arc Safe Storage", "com.thebrowser.Browser"),
            ]
        case .chrome:
            return [("Chrome Safe Storage", "Chrome")]
        case .edge:
            return [("Microsoft Edge Safe Storage", "Microsoft Edge")]
        case .brave:
            return [("Brave Safe Storage", "Brave")]
        case .chromium:
            return [("Chromium Safe Storage", "Chromium")]
        case .opera:
            return [
                ("Opera Safe Storage", "Opera"),
                ("Opera Safe Storage", "Opera Stable"),
            ]
        case .operaGX:
            return [
                ("Opera Safe Storage", "Opera GX Stable"),
                ("Opera Safe Storage", "Opera GX"),
            ]
        case .vivaldi:
            return [("Vivaldi Safe Storage", "Vivaldi")]
        case .firefox:
            return []
        case .safari:
            return []
        }
    }

    private func pbkdf2SHA1(password: String, salt: String, rounds: Int, keyByteCount: Int) -> Data? {
        guard let saltData = salt.data(using: .utf8) else {
            return nil
        }

        var keyData = Data(repeating: 0, count: keyByteCount)
        let keyLength = keyData.count
        let result = keyData.withUnsafeMutableBytes { keyBytes in
            password.utf8CString.withUnsafeBytes { passBytes in
                saltData.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBytes.bindMemory(to: Int8.self).baseAddress,
                        passBytes.count - 1,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        UInt32(rounds),
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }

        return result == kCCSuccess ? keyData : nil
    }

    private func aesCBCDecrypt(ciphertext: Data, key: Data, iv: Data) -> Data? {
        var outLength = 0
        var outData = Data(repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        let outCapacity = outData.count
        let status = outData.withUnsafeMutableBytes { outBytes in
            ciphertext.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress,
                            ciphertext.count,
                            outBytes.baseAddress,
                            outCapacity,
                            &outLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        outData.count = outLength
        return outData
    }

    private func cleanCookieValue(_ value: String) -> String {
        var index = value.startIndex
        while index < value.endIndex, value[index].unicodeScalars.allSatisfy({ $0.value < 0x20 }) {
            index = value.index(after: index)
        }
        return String(value[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedSQLitePath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/sqlite3",
            "/usr/local/bin/sqlite3",
            "/usr/bin/sqlite3",
        ]
        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }

    private func browserLabel(_ browser: KimiBrowserKind) -> String {
        switch browser {
        case .arc:
            return "Auto:Arc"
        case .chrome:
            return "Auto:Chrome"
        case .safari:
            return "Auto:Safari"
        case .edge:
            return "Auto:Edge"
        case .brave:
            return "Auto:Brave"
        case .chromium:
            return "Auto:Chromium"
        case .firefox:
            return "Auto:Firefox"
        case .opera:
            return "Auto:Opera"
        case .operaGX:
            return "Auto:OperaGX"
        case .vivaldi:
            return "Auto:Vivaldi"
        }
    }
}

actor WebOverlayRetryBackoff {
    private var blockedUntil: [String: Date] = [:]

    func shouldAttempt(for key: String, forceRefresh: Bool, now: Date = Date()) -> Bool {
        if forceRefresh {
            return true
        }
        guard let deadline = blockedUntil[key] else {
            return true
        }
        return now >= deadline
    }

    func markFailure(for key: String, interval: TimeInterval, now: Date = Date()) {
        blockedUntil[key] = now.addingTimeInterval(max(0, interval))
    }

    func clearFailure(for key: String) {
        blockedUntil.removeValue(forKey: key)
    }
}

private enum HexDataParser {
    static func data(from hexString: String) -> Data? {
        let cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count % 2 == 0 else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        for _ in 0..<(cleaned.count / 2) {
            let next = cleaned.index(index, offsetBy: 2)
            let byteString = cleaned[index..<next]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
