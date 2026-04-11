import Foundation

final class KimiProvider: UsageProvider, @unchecked Sendable {
    private let session: URLSession
    private let keychain: KeychainService
    private let browserCookieService: KimiBrowserCookieService
    private let tokenResolverOverride: (() throws -> (token: String, source: String))?

    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        keychain: KeychainService,
        browserCookieService: KimiBrowserCookieService = KimiBrowserCookieService(),
        tokenResolverOverride: (() throws -> (token: String, source: String))? = nil
    ) {
        self.descriptor = descriptor
        self.session = session
        self.keychain = keychain
        self.browserCookieService = browserCookieService
        self.tokenResolverOverride = tokenResolverOverride
    }

    func fetch() async throws -> UsageSnapshot {
        let baseURL = URL(string: descriptor.baseURL ?? "https://www.kimi.com")!
        let resolved = try (tokenResolverOverride?() ?? resolveToken())
        let authToken = Self.normalizeToken(resolved.token)
        let sessionInfo = Self.decodeSessionInfo(from: authToken)

        var request = URLRequest(url: baseURL.appending(path: "/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = #"{"scope":["FEATURE_CODING"]}"#.data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("kimi-auth=\(authToken)", forHTTPHeaderField: "Cookie")
        request.setValue("https://www.kimi.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.kimi.com/code/console", forHTTPHeaderField: "Referer")
        request.setValue(Locale.preferredLanguages.first ?? "zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
        request.setValue(Locale.current.identifier, forHTTPHeaderField: "x-language")
        request.setValue("web", forHTTPHeaderField: "x-msh-platform")
        request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "r-timezone")
        if let deviceId = sessionInfo?.deviceId, !deviceId.isEmpty {
            request.setValue(deviceId, forHTTPHeaderField: "x-msh-device-id")
        }
        if let sessionId = sessionInfo?.sessionId, !sessionId.isEmpty {
            request.setValue(sessionId, forHTTPHeaderField: "x-msh-session-id")
        }
        if let trafficId = sessionInfo?.trafficId, !trafficId.isEmpty {
            request.setValue(trafficId, forHTTPHeaderField: "x-traffic-id")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            if let message = Self.extractErrorMessage(from: data), !message.isEmpty {
                throw ProviderError.unauthorizedDetail(message)
            }
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            if let message = Self.extractErrorMessage(from: data), !message.isEmpty {
                throw ProviderError.invalidResponse("http \(http.statusCode): \(message)")
            }
            throw ProviderError.invalidResponse("http \(http.statusCode)")
        }

        return try Self.parseSnapshot(data: data, descriptor: descriptor, authSource: resolved.source)
    }

    static func parseSnapshot(data: Data, descriptor: ProviderDescriptor, authSource: String, now: Date = Date()) throws -> UsageSnapshot {
        let envelope: KimiUsageEnvelope
        do {
            envelope = try JSONDecoder().decode(KimiUsageEnvelope.self, from: data)
        } catch {
            throw ProviderError.invalidResponse("Kimi usage decode failed")
        }

        guard let codingUsage = envelope.usages.first(where: { $0.scope == "FEATURE_CODING" }) ?? envelope.usages.first else {
            throw ProviderError.invalidResponse("missing usages")
        }
        guard let weekly = codingUsage.detail else {
            throw ProviderError.invalidResponse("missing weekly detail")
        }
        guard let window = codingUsage.limits.first(where: { $0.window.duration == 300 && $0.window.timeUnit == "TIME_UNIT_MINUTE" })?.detail
            ?? codingUsage.limits.first?.detail else {
            throw ProviderError.invalidResponse("missing 5-hour limit detail")
        }

        let weeklyPercent = ratioPercent(remaining: weekly.remaining, limit: weekly.limit)
        let windowPercent = ratioPercent(remaining: window.remaining, limit: window.limit)
        let minPercent = min(weeklyPercent, windowPercent)
        let status: SnapshotStatus = minPercent <= descriptor.threshold.lowRemaining ? .warning : .ok

        var rawMeta: [String: String] = [
            "kimi.authSource": authSource,
            "kimi.weekly.limit": formatNumber(weekly.limit),
            "kimi.weekly.used": formatNumber(weekly.used),
            "kimi.weekly.remaining": formatNumber(weekly.remaining),
            "kimi.weekly.remainingPercent": formatNumber(weeklyPercent),
            "kimi.window5h.limit": formatNumber(window.limit),
            "kimi.window5h.used": formatNumber(window.used),
            "kimi.window5h.remaining": formatNumber(window.remaining),
            "kimi.window5h.remainingPercent": formatNumber(windowPercent),
        ]
        if let epoch = parseISO8601ToEpoch(weekly.resetTime) {
            rawMeta["kimi.weekly.resetAt"] = String(epoch)
        }
        if let epoch = parseISO8601ToEpoch(window.resetTime) {
            rawMeta["kimi.window5h.resetAt"] = String(epoch)
        }

        let note = "Weekly \(Int(weekly.remaining))/\(Int(weekly.limit)) | 5h \(Int(window.remaining))/\(Int(window.limit))"
        let quotaWindows = [
            UsageQuotaWindow(
                id: "\(descriptor.id)-weekly",
                title: "Weekly",
                remainingPercent: weeklyPercent,
                usedPercent: max(0, 100 - weeklyPercent),
                resetAt: Self.parseISO8601ToEpoch(weekly.resetTime).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                kind: .weekly
            ),
            UsageQuotaWindow(
                id: "\(descriptor.id)-5h",
                title: "5h",
                remainingPercent: windowPercent,
                usedPercent: max(0, 100 - windowPercent),
                resetAt: Self.parseISO8601ToEpoch(window.resetTime).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                kind: .session
            )
        ]

        return UsageSnapshot(
            source: descriptor.id,
            status: status,
            remaining: minPercent,
            used: 100 - minPercent,
            limit: 100,
            unit: "%",
            updatedAt: now,
            note: note,
            quotaWindows: quotaWindows,
            sourceLabel: authSource,
            accountLabel: nil,
            extras: [:],
            rawMeta: rawMeta
        )
    }

    private func resolveToken() throws -> (token: String, source: String) {
        guard let kimiConfig = descriptor.kimiConfig else {
            throw ProviderError.invalidResponse("missing kimi config")
        }
        guard let service = descriptor.auth.keychainService else {
            throw ProviderError.missingCredential("AIBalanceMonitor")
        }

        let manualAccount = kimiConfig.manualTokenAccount
        if let manual = keychain.readToken(service: service, account: manualAccount), !manual.isEmpty {
            let normalized = Self.normalizeToken(manual)
            if !normalized.isEmpty, !KimiJWT.isExpired(normalized) {
                return (normalized, "manual")
            }
            if kimiConfig.authMode == .manual {
                throw ProviderError.unauthorized
            }
        } else if kimiConfig.authMode == .manual {
            throw ProviderError.missingCredential(manualAccount)
        }

        guard kimiConfig.autoCookieEnabled else {
            throw ProviderError.missingCredential(manualAccount)
        }

        let autoAccount = "kimi.com/kimi-auth-auto"
        if let cached = keychain.readToken(service: service, account: autoAccount),
           !cached.isEmpty {
            let normalized = Self.normalizeToken(cached)
            if !normalized.isEmpty, !KimiJWT.isExpired(normalized) {
                return (normalized, "auto:cache")
            }
        }

        if let detected = browserCookieService.detectKimiAuthToken(order: kimiConfig.browserOrder),
           !KimiJWT.isExpired(Self.normalizeToken(detected.token)) {
            let normalized = Self.normalizeToken(detected.token)
            _ = keychain.saveToken(normalized, service: service, account: autoAccount)
            return (normalized, detected.source)
        }

        throw ProviderError.missingCredential(autoAccount)
    }

    private static func ratioPercent(remaining: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        return min(100, max(0, (remaining / limit) * 100))
    }

    private static func parseISO8601ToEpoch(_ raw: String?) -> Int? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) {
            return Int(date.timeIntervalSince1970)
        }
        let fallback = ISO8601DateFormatter()
        if let date = fallback.date(from: raw) {
            return Int(date.timeIntervalSince1970)
        }
        return nil
    }

    private static func formatNumber(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func normalizeToken(_ raw: String) -> String {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("Bearer ") || token.hasPrefix("bearer ") {
            token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if token.hasPrefix("\""), token.hasSuffix("\""), token.count >= 2 {
            token = String(token.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let decoded = token.removingPercentEncoding, decoded.contains(".") {
            token = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return token
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let message = root["message"] as? String {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let error = root["error"] as? String {
            return error.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let details = root["details"] as? String {
            return details.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let message = (root["error"] as? [String: Any])?["message"] as? String {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func decodeSessionInfo(from token: String) -> KimiSessionInfo? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        guard let payloadData = KimiJWT.decodeBase64URL(String(parts[1])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }
        return KimiSessionInfo(
            deviceId: payload["device_id"] as? String,
            sessionId: payload["ssid"] as? String,
            trafficId: payload["sub"] as? String
        )
    }
}

private struct KimiUsageEnvelope: Decodable {
    let usages: [KimiScopeUsage]
}

private struct KimiScopeUsage: Decodable {
    let scope: String
    let detail: KimiUsageDetail?
    let limits: [KimiWindowUsage]
}

private struct KimiWindowUsage: Decodable {
    let window: KimiWindow
    let detail: KimiUsageDetail
}

private struct KimiWindow: Decodable {
    let duration: Int
    let timeUnit: String
}

private struct KimiUsageDetail: Decodable {
    let limit: Double
    let used: Double
    let remaining: Double
    let resetTime: String?

    private enum CodingKeys: String, CodingKey {
        case limit
        case used
        case remaining
        case resetTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limit = try Self.decodeDouble(container, key: .limit)
        remaining = try Self.decodeDouble(container, key: .remaining)
        if let directUsed = try? Self.decodeDouble(container, key: .used) {
            used = directUsed
        } else {
            used = max(0, limit - remaining)
        }
        resetTime = try container.decodeIfPresent(String.self, forKey: .resetTime)
    }

    private static func decodeDouble(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Double {
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let string = try? container.decode(String.self, forKey: key),
           let value = Double(string) {
            return value
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "invalid number")
    }
}

enum KimiJWT {
    static func isExpired(_ token: String, now: Date = Date()) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return true }
        guard let payloadData = decodeBase64URL(String(parts[1])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let expNumber = payload["exp"] as? NSNumber else {
            return true
        }
        let exp = expNumber.doubleValue
        return exp <= now.timeIntervalSince1970 + 5
    }

    static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

private struct KimiSessionInfo {
    let deviceId: String?
    let sessionId: String?
    let trafficId: String?
}
