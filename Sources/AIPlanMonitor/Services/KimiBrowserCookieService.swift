import Foundation
import CommonCrypto
import LocalAuthentication
import Security

struct KimiDetectedToken: Equatable {
    let token: String
    let source: String
}

final class KimiBrowserCookieService {
    private let fileManager: FileManager
    private var safeStorageCache: [KimiBrowserKind: String] = [:]
    private let browserOrderDefault: [KimiBrowserKind] = [.arc, .chrome, .safari, .edge, .brave, .chromium]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func detectKimiAuthToken(order: [KimiBrowserKind]) -> KimiDetectedToken? {
        for browser in order {
            if let token = tokenFromBrowser(browser, cookieName: "kimi-auth", hostContains: "kimi.com") {
                return KimiDetectedToken(token: token, source: browserLabel(browser))
            }
            if let token = bestBearerTokenFromBrowser(browser: browser, hostCandidates: ["www.kimi.com", "kimi.com"]) {
                return KimiDetectedToken(token: token, source: "\(browserLabel(browser)):localStorage")
            }
        }
        return nil
    }

    func detectCookieHeader(host: String, order: [KimiBrowserKind]? = nil) -> KimiDetectedToken? {
        let actualOrder = order ?? browserOrderDefault
        for browser in actualOrder {
            for path in candidateCookiePaths(for: browser) {
                if let header = cookieHeaderFromCookieDatabase(path: path, browser: browser, hostContains: host),
                   !header.isEmpty {
                    return KimiDetectedToken(token: header, source: "\(browserLabel(browser)):cookie")
                }
            }
        }
        return nil
    }

    func detectBearerToken(host: String, order: [KimiBrowserKind]? = nil) -> KimiDetectedToken? {
        detectBearerTokenCandidates(host: host, order: order).first
    }

    func detectBearerTokenCandidates(host: String, order: [KimiBrowserKind]? = nil) -> [KimiDetectedToken] {
        let actualOrder = order ?? browserOrderDefault
        var candidates: [(token: String, source: String, exp: TimeInterval?, score: Int)] = []
        for browser in actualOrder {
            for path in candidateBearerStoragePaths(for: browser) {
                let perPath = bearerTokenCandidatesFromStorage(path: path, host: host)
                for candidate in perPath {
                    candidates.append((
                        token: candidate.token,
                        source: "\(browserLabel(browser)):localStorage",
                        exp: candidate.exp,
                        score: candidate.score
                    ))
                }
            }
        }
        guard !candidates.isEmpty else { return [] }

        candidates.sort { lhs, rhs in
            let lhsExp = lhs.exp ?? -1
            let rhsExp = rhs.exp ?? -1
            if lhsExp != rhsExp { return lhsExp > rhsExp }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.token.count > rhs.token.count
        }
        var seen = Set<String>()
        var output: [KimiDetectedToken] = []
        for candidate in candidates {
            if seen.insert(candidate.token).inserted {
                output.append(KimiDetectedToken(token: candidate.token, source: candidate.source))
            }
        }
        return output
    }

    private struct BearerTokenCandidate {
        let token: String
        let exp: TimeInterval?
        let score: Int
    }

    private func bestBearerTokenFromBrowser(browser: KimiBrowserKind, hostCandidates: [String]) -> String? {
        var candidates: [BearerTokenCandidate] = []
        for path in candidateBearerStoragePaths(for: browser) {
            for host in hostCandidates {
                candidates.append(contentsOf: bearerTokenCandidatesFromStorage(path: path, host: host))
            }
        }
        guard !candidates.isEmpty else { return nil }
        candidates.sort { lhs, rhs in
            let lhsExp = lhs.exp ?? -1
            let rhsExp = rhs.exp ?? -1
            if lhsExp != rhsExp { return lhsExp > rhsExp }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.token.count > rhs.token.count
        }
        return candidates[0].token
    }

    private func tokenFromBrowser(_ browser: KimiBrowserKind, cookieName: String, hostContains: String) -> String? {
        for path in candidateCookiePaths(for: browser) {
            if let token = tokenFromCookieDatabase(path: path, browser: browser, cookieName: cookieName, hostContains: hostContains) {
                return token
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
            ]
        case .edge:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/Microsoft Edge")
        case .brave:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/BraveSoftware/Brave-Browser")
        case .chromium:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/Chromium")
        }
    }

    private func candidateLocalStoragePaths(for browser: KimiBrowserKind) -> [String] {
        guard let base = browserUserDataPath(for: browser) else { return [] }

        var result: [String] = []
        let baseURL = URL(fileURLWithPath: base)
        let keys: [URLResourceKey] = [.isDirectoryKey]
        if let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: keys) {
            for case let url as URL in enumerator {
                guard url.lastPathComponent == "leveldb",
                      url.path.contains("/Local Storage/") else { continue }
                result.append(url.path)
            }
        }
        return Array(Set(result)).sorted()
    }

    private func candidateSessionStoragePaths(for browser: KimiBrowserKind) -> [String] {
        guard let base = browserUserDataPath(for: browser) else { return [] }

        var result: [String] = []
        let baseURL = URL(fileURLWithPath: base)
        let keys: [URLResourceKey] = [.isDirectoryKey]
        if let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: keys) {
            for case let url as URL in enumerator {
                guard url.lastPathComponent == "Session Storage" else { continue }
                result.append(url.path)
            }
        }
        return Array(Set(result)).sorted()
    }

    private func candidateIndexedDBPaths(for browser: KimiBrowserKind) -> [String] {
        guard let base = browserUserDataPath(for: browser) else { return [] }

        var result: [String] = []
        let baseURL = URL(fileURLWithPath: base)
        let keys: [URLResourceKey] = [.isDirectoryKey]
        if let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: keys) {
            for case let url as URL in enumerator {
                guard url.path.hasSuffix(".indexeddb.leveldb") else { continue }
                result.append(url.path)
            }
        }
        return Array(Set(result)).sorted()
    }

    private func candidateBearerStoragePaths(for browser: KimiBrowserKind) -> [String] {
        let merged = candidateLocalStoragePaths(for: browser)
            + candidateSessionStoragePaths(for: browser)
            + candidateIndexedDBPaths(for: browser)
        return Array(Set(merged)).sorted()
    }

    private func browserUserDataPath(for browser: KimiBrowserKind) -> String? {
        let home = NSHomeDirectory()
        switch browser {
        case .arc:
            return "\(home)/Library/Application Support/Arc/User Data"
        case .chrome:
            return "\(home)/Library/Application Support/Google/Chrome"
        case .edge:
            return "\(home)/Library/Application Support/Microsoft Edge"
        case .brave:
            return "\(home)/Library/Application Support/BraveSoftware/Brave-Browser"
        case .chromium:
            return "\(home)/Library/Application Support/Chromium"
        case .safari:
            return nil
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

    private func tokenFromCookieDatabase(path: String, browser: KimiBrowserKind, cookieName: String, hostContains: String) -> String? {
        guard fileManager.fileExists(atPath: path) else { return nil }
        guard let sqlite = resolvedSQLitePath() else { return nil }

        let tempDB = "\(NSTemporaryDirectory())/kimi_cookie_\(UUID().uuidString).sqlite"
        defer { try? fileManager.removeItem(atPath: tempDB) }

        do {
            try fileManager.copyItem(atPath: path, toPath: tempDB)
        } catch {
            return nil
        }

        let queries = [
            "SELECT value, hex(encrypted_value) FROM cookies WHERE name='\(cookieName)' AND host_key LIKE '%\(hostContains)%' ORDER BY LENGTH(value) DESC, LENGTH(encrypted_value) DESC;",
            "SELECT value, hex(encrypted_value) FROM cookies WHERE name='\(cookieName)' AND domain LIKE '%\(hostContains)%' ORDER BY LENGTH(value) DESC, LENGTH(encrypted_value) DESC;",
            "SELECT value, hex(encrypted_value) FROM Cookies WHERE name='\(cookieName)' AND host LIKE '%\(hostContains)%' ORDER BY LENGTH(value) DESC, LENGTH(encrypted_value) DESC;",
            "SELECT value, hex(encrypted_value) FROM Cookies WHERE name='\(cookieName)' AND domain LIKE '%\(hostContains)%' ORDER BY LENGTH(value) DESC, LENGTH(encrypted_value) DESC;",
        ]

        for query in queries {
            guard let raw = runProcess(executable: sqlite, arguments: ["-separator", "\t", tempDB, query]) else { continue }
            for lineSub in raw.split(separator: "\n") {
                let line = String(lineSub)
                if line.isEmpty { continue }
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

        let tempDB = "\(NSTemporaryDirectory())/relay_cookie_\(UUID().uuidString).sqlite"
        defer { try? fileManager.removeItem(atPath: tempDB) }
        do {
            try fileManager.copyItem(atPath: path, toPath: tempDB)
        } catch {
            return nil
        }

        let query = "SELECT name, value, hex(encrypted_value) FROM cookies WHERE host_key LIKE '%\(hostContains)%' ORDER BY name;"
        guard let raw = runProcess(executable: sqlite, arguments: ["-separator", "\t", tempDB, query]) else { return nil }
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

        guard !pairs.isEmpty else { return nil }
        return pairs.joined(separator: "; ")
    }

    private func bearerTokenCandidatesFromStorage(path: String, host: String) -> [BearerTokenCandidate] {
        guard fileManager.fileExists(atPath: path) else { return [] }
        guard let files = try? fileManager.contentsOfDirectory(atPath: path) else { return [] }

        let normalizedHost = host.lowercased()
        let hostMarkers = [
            "_https://\(normalizedHost)",
            "_http://\(normalizedHost)",
            normalizedHost,
        ]
        let keyHints = ["auth_token", "access_token", "token", "jwt", "id_token", "authorization", "hongmacode_token"]
        let jwtRegex = try? NSRegularExpression(pattern: #"([A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,})"#)
        let skRegex = try? NSRegularExpression(pattern: #"(sk-[A-Za-z0-9][A-Za-z0-9_-]{8,})"#)
        let keyedTokenRegex = try? NSRegularExpression(
            pattern: #"(?i)(hongmacode_token|auth_token|access_token|id_token|refresh_token|token|authorization)[^A-Za-z0-9]{0,24}(?:bearer\s+)?([A-Za-z0-9._\-+/=]{16,})"#
        )
        var candidates: [BearerTokenCandidate] = []

        for name in files where name.hasSuffix(".log") || name.hasSuffix(".ldb") || name.hasPrefix("MANIFEST-") {
            let filePath = path + "/" + name
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath), options: [.mappedIfSafe]),
                  let text = String(data: data, encoding: .isoLatin1) else {
                continue
            }
            let lowered = text.lowercased()
            let hostMatchedByPath = path.lowercased().contains(normalizedHost)
            let hostMatchedByMarker = hostMarkers.contains(where: { lowered.contains($0) })
            let hostMatchedBySiteKey: Bool
            if normalizedHost == "hongmacc.com" {
                hostMatchedBySiteKey = lowered.contains("hongmacode_token")
            } else {
                hostMatchedBySiteKey = false
            }
            let hostMatched = hostMatchedByPath || hostMatchedByMarker || hostMatchedBySiteKey
            guard hostMatched else { continue }

            let ns = text as NSString
            let fullRange = NSRange(location: 0, length: ns.length)
            let jwtMatches = jwtRegex?.matches(in: text, options: [], range: fullRange) ?? []
            for match in jwtMatches where match.numberOfRanges > 1 {
                appendCandidate(
                    token: ns.substring(with: match.range(at: 1)),
                    around: match.range(at: 1),
                    nsText: ns,
                    normalizedHost: normalizedHost,
                    keyHints: keyHints,
                    candidates: &candidates
                )
            }

            let skMatches = skRegex?.matches(in: text, options: [], range: fullRange) ?? []
            for match in skMatches where match.numberOfRanges > 1 {
                appendCandidate(
                    token: ns.substring(with: match.range(at: 1)),
                    around: match.range(at: 1),
                    nsText: ns,
                    normalizedHost: normalizedHost,
                    keyHints: keyHints,
                    candidates: &candidates
                )
            }

            let keyedMatches = keyedTokenRegex?.matches(in: text, options: [], range: fullRange) ?? []
            for match in keyedMatches where match.numberOfRanges > 2 {
                appendCandidate(
                    token: ns.substring(with: match.range(at: 2)),
                    around: match.range(at: 2),
                    nsText: ns,
                    normalizedHost: normalizedHost,
                    keyHints: keyHints,
                    candidates: &candidates
                )
            }
        }

        var unique: [String: BearerTokenCandidate] = [:]
        for candidate in candidates {
            if let current = unique[candidate.token] {
                if candidate.score > current.score {
                    unique[candidate.token] = candidate
                }
            } else {
                unique[candidate.token] = candidate
            }
        }

        return Array(unique.values)
    }

    private func appendCandidate(
        token rawToken: String,
        around range: NSRange,
        nsText: NSString,
        normalizedHost: String,
        keyHints: [String],
        candidates: inout [BearerTokenCandidate]
    ) {
        var token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("Bearer ") || token.hasPrefix("bearer ") {
            token = String(token.dropFirst(7))
        }
        if let decoded = token.removingPercentEncoding, !decoded.isEmpty {
            token = decoded
        }
        token = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`;,)}]"))
        token = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`{(["))
        guard token.count >= 16 else { return }
        guard token.range(of: #"^[A-Za-z0-9._-]{16,}$"#, options: .regularExpression) != nil else { return }
        if token.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#, options: .regularExpression) != nil {
            return
        }
        let looksJWT = token.split(separator: ".").count >= 3
        let looksSK = token.lowercased().hasPrefix("sk-")
        let looksLongOpaque = token.count >= 80
        guard looksJWT || looksSK || looksLongOpaque else { return }

        let windowStart = max(0, range.location - 260)
        let windowLen = min(nsText.length - windowStart, range.length + 520)
        let window = nsText.substring(with: NSRange(location: windowStart, length: windowLen)).lowercased()

        var score = 0
        if window.contains(normalizedHost) { score += 4 }
        if keyHints.contains(where: { window.contains($0) }) { score += 6 }
        if window.contains("bearer") { score += 2 }
        if looksSK { score += 8 }
        if looksJWT { score += 4 }
        if token.count >= 64 { score += 2 }

        let exp = jwtExpiration(token)
        if let exp {
            if exp > Date().timeIntervalSince1970 {
                score += 8
            } else {
                score -= 4
            }
        }

        guard score >= 6 else { return }
        candidates.append(BearerTokenCandidate(token: token, exp: exp, score: score))
    }

    private func decryptChromiumCookieHex(_ hex: String, browser: KimiBrowserKind) -> String? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let encrypted = Data(hexString: cleaned),
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
            if let password = findGenericPassword(service: label.service, account: label.account), !password.isEmpty {
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
        case .safari:
            return []
        }
    }

    private func findGenericPassword(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: nonInteractiveContext(),
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func nonInteractiveContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
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

    private func jwtExpiration(_ token: String) -> TimeInterval? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let payloadData = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let exp = json["exp"] as? NSNumber else {
            return nil
        }
        return exp.doubleValue
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

    private func runProcess(executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private func browserLabel(_ browser: KimiBrowserKind) -> String {
        switch browser {
        case .arc:
            return "auto:Arc"
        case .chrome:
            return "auto:Chrome"
        case .safari:
            return "auto:Safari"
        case .edge:
            return "auto:Edge"
        case .brave:
            return "auto:Brave"
        case .chromium:
            return "auto:Chromium"
        }
    }
}

private extension Data {
    init?(hexString: String) {
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
        self = data
    }
}
