import Foundation

final class OpenProvider: UsageProvider, @unchecked Sendable {
    let descriptor: ProviderDescriptor
    private let session: URLSession
    private let keychain: KeychainService

    init(descriptor: ProviderDescriptor, session: URLSession = .shared, keychain: KeychainService) {
        self.descriptor = descriptor
        self.session = session
        self.keychain = keychain
    }

    func fetch() async throws -> UsageSnapshot {
        let baseURL = URL(string: descriptor.baseURL ?? "https://open.ailinyu.de")!
        var firstError: Error?
        var tokenChannel: TokenChannelResult?
        var accountChannel: AccountChannelResult?

        let openConfig = descriptor.openConfig

        if openConfig?.tokenUsageEnabled ?? true {
            do {
                tokenChannel = try await fetchTokenUsageChannel(baseURL: baseURL)
            } catch {
                firstError = firstError ?? error
            }
        }

        if let accountConfig = openConfig?.accountBalance, accountConfig.enabled {
            do {
                accountChannel = try await fetchAccountBalanceChannel(baseURL: baseURL, config: accountConfig)
            } catch {
                firstError = firstError ?? error
            }
        }

        guard tokenChannel != nil || accountChannel != nil else {
            throw firstError ?? ProviderError.unavailable("No enabled data channel for \(descriptor.name)")
        }

        let remaining = accountChannel?.remaining ?? tokenChannel?.remaining
        let used = accountChannel?.used ?? tokenChannel?.used
        let limit = accountChannel?.limit ?? tokenChannel?.limit
        let unit = accountChannel?.unit ?? tokenChannel?.unit ?? "quota"

        let status: SnapshotStatus
        if let remaining {
            status = remaining <= descriptor.threshold.lowRemaining ? .warning : .ok
        } else {
            status = .ok
        }

        var noteParts: [String] = []
        var rawMeta: [String: String] = [:]

        if let accountChannel {
            noteParts.append(accountChannel.note)
            for (k, v) in accountChannel.rawMeta {
                rawMeta["account.\(k)"] = v
            }
        }

        if let tokenChannel {
            noteParts.append(tokenChannel.note)
            for (k, v) in tokenChannel.rawMeta {
                rawMeta["token.\(k)"] = v
            }
        }

        if noteParts.isEmpty {
            noteParts.append("No detail")
        }

        return UsageSnapshot(
            source: descriptor.id,
            status: status,
            remaining: remaining,
            used: used,
            limit: limit,
            unit: unit,
            updatedAt: Date(),
            note: noteParts.joined(separator: " | "),
            rawMeta: rawMeta
        )
    }

    private func fetchTokenUsageChannel(baseURL: URL) async throws -> TokenChannelResult {
        guard let service = descriptor.auth.keychainService,
              let account = descriptor.auth.keychainAccount,
              let token = keychain.readToken(service: service, account: account),
              !token.isEmpty else {
            throw ProviderError.missingCredential(descriptor.auth.keychainAccount ?? descriptor.id)
        }

        let tokenUsage = try await request(
            url: baseURL.appending(path: "/api/usage/token/"),
            bearerToken: token,
            type: OpenTokenUsageEnvelope.self
        )

        let subscription = try? await request(
            url: baseURL.appending(path: "/v1/dashboard/billing/subscription"),
            bearerToken: token,
            type: OpenBillingSubscription.self
        )

        let usage = try? await request(
            url: baseURL.appending(path: "/v1/dashboard/billing/usage"),
            bearerToken: token,
            type: OpenBillingUsage.self
        )

        let unlimited = tokenUsage.data.unlimitedQuota
        let remaining = unlimited ? nil : tokenUsage.data.totalAvailable
        let used = tokenUsage.data.totalUsed
        let softLimit = subscription?.softLimitUSD ?? tokenUsage.data.totalGranted
        let hardLimit = subscription?.hardLimitUSD ?? softLimit
        let limit = unlimited ? nil : max(tokenUsage.data.totalGranted, softLimit)

        let note: String
        if unlimited {
            if let usage {
                note = "Token unlimited | billing usage \(String(format: "%.2f", usage.totalUsage))"
            } else {
                note = "Token unlimited"
            }
        } else {
            if let usage {
                note = "Token remaining \(String(format: "%.2f", remaining ?? 0)) | billing usage \(String(format: "%.2f", usage.totalUsage))"
            } else {
                note = "Token remaining \(String(format: "%.2f", remaining ?? 0))"
            }
        }

        var meta: [String: String] = [
            "tokenName": tokenUsage.data.name,
            "unlimitedQuota": String(unlimited),
            "softLimitUsd": String(softLimit),
            "hardLimitUsd": String(hardLimit)
        ]
        if let usage {
            meta["billingTotalUsage"] = String(usage.totalUsage)
        } else {
            meta["billingTotalUsage"] = "n/a"
        }

        return TokenChannelResult(
            remaining: remaining,
            used: used,
            limit: limit,
            unit: "quota",
            note: note,
            rawMeta: meta
        )
    }

    private func fetchAccountBalanceChannel(baseURL: URL, config: RelayAccountBalanceConfig) async throws -> AccountChannelResult {
        guard let service = config.auth.keychainService,
              let account = config.auth.keychainAccount,
              let token = keychain.readToken(service: service, account: account),
              !token.isEmpty else {
            throw ProviderError.missingCredential(config.auth.keychainAccount ?? "\(descriptor.id)/system-token")
        }

        let endpointPath = normalizedPath(config.endpointPath)
        let url = baseURL.appending(path: endpointPath)

        var headers: [String: String] = [:]
        let authHeader = config.authHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Authorization" : config.authHeader
        let authScheme = config.authScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        headers[authHeader] = authScheme.isEmpty ? token : "\(authScheme) \(token)"

        if let userID = config.userID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !userID.isEmpty {
            let userHeader = config.userIDHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New-Api-User" : config.userIDHeader
            headers[userHeader] = userID
        }

        let root = try await requestJSON(
            url: url,
            headers: headers,
            method: config.requestMethod,
            bodyJSON: config.requestBodyJSON
        )

        if let successPath = config.successJSONPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !successPath.isEmpty,
           let successValue = value(at: successPath, in: root),
           let success = coerceBool(successValue),
           !success {
            throw ProviderError.invalidResponse("account balance endpoint reported failure at \(successPath)")
        }

        guard var remaining = numericValue(at: config.remainingJSONPath, in: root) else {
            throw ProviderError.invalidResponse("missing remaining path \(config.remainingJSONPath)")
        }

        var used = config.usedJSONPath.flatMap { path in
            numericValue(at: path, in: root)
        }

        var limit = config.limitJSONPath.flatMap { path in
            numericValue(at: path, in: root)
        }
        if limit == nil, let used {
            limit = max(0, remaining + used)
        }

        var unit = config.unit.isEmpty ? "quota" : config.unit
        var extraMeta: [String: String] = [:]
        if shouldApplyAilinyuQuotaConversion(baseURL: baseURL, config: config) {
            let converted = try? await convertAilinyuQuotaToDisplayAmount(
                baseURL: baseURL,
                headers: headers,
                quota: remaining
            )
            if let converted {
                remaining = converted.remaining
                used = used.map { $0 / converted.quotaPerUnit * converted.rate }
                limit = limit.map { $0 / converted.quotaPerUnit * converted.rate }
                unit = converted.unit
                extraMeta["displayType"] = converted.displayType
                extraMeta["quotaPerUnit"] = String(converted.quotaPerUnit)
                extraMeta["displayRate"] = String(converted.rate)
            }
        }

        let note = "Account remaining \(String(format: "%.2f", remaining))"
        return AccountChannelResult(
            remaining: remaining,
            used: used,
            limit: limit,
            unit: unit,
            note: note,
            rawMeta: [
                "endpointPath": endpointPath,
                "requestMethod": (config.requestMethod ?? "GET"),
                "remainingPath": config.remainingJSONPath,
                "usedPath": config.usedJSONPath ?? "",
                "limitPath": config.limitJSONPath ?? "",
                "userID": config.userID ?? ""
            ].merging(extraMeta, uniquingKeysWith: { _, rhs in rhs })
        )
    }

    private func normalizedPath(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "/api/user/self" }
        if trimmed.hasPrefix("/") {
            return trimmed
        }
        return "/" + trimmed
    }

    private func requestJSON(url: URL, headers: [String: String], method: String?, bodyJSON: String?) async throws -> Any {
        var req = URLRequest(url: url)
        let normalizedMethod = (method ?? "GET").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        req.httpMethod = normalizedMethod.isEmpty ? "GET" : normalizedMethod
        req.timeoutInterval = 15
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        if let bodyJSON {
            let trimmedBody = bodyJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedBody.isEmpty, req.httpMethod != "GET" {
                req.httpBody = trimmedBody.data(using: .utf8)
                if req.value(forHTTPHeaderField: "Content-Type") == nil {
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("non-http response")
        }
        if http.statusCode == 401 {
            if let message = extractErrorMessage(from: data), !message.isEmpty {
                throw ProviderError.unauthorizedDetail(message)
            }
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("http \(http.statusCode)")
        }

        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ProviderError.invalidResponse("account balance JSON decode failed")
        }
    }

    private func value(at path: String, in root: Any) -> Any? {
        let steps = path.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        guard !steps.isEmpty else { return nil }
        var current: Any? = root
        for step in steps {
            if let index = Int(step), let array = current as? [Any], array.indices.contains(index) {
                current = array[index]
                continue
            }
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[step]
        }
        return current
    }

    private func numericValue(at path: String, in root: Any) -> Double? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("sum("), trimmed.hasSuffix(")") {
            let inner = String(trimmed.dropFirst(4).dropLast())
            let numbers = values(at: inner, in: root).compactMap(coerceDouble)
            guard !numbers.isEmpty else { return nil }
            return numbers.reduce(0, +)
        }

        return value(at: trimmed, in: root).flatMap(coerceDouble)
    }

    private func values(at path: String, in root: Any) -> [Any] {
        let steps = path.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        guard !steps.isEmpty else { return [] }
        return collectValues(current: root, steps: steps, index: 0)
    }

    private func collectValues(current: Any, steps: [String], index: Int) -> [Any] {
        guard index < steps.count else { return [current] }
        let step = steps[index]

        if step == "*" {
            guard let array = current as? [Any] else { return [] }
            return array.flatMap { collectValues(current: $0, steps: steps, index: index + 1) }
        }

        if let i = Int(step), let array = current as? [Any], array.indices.contains(i) {
            return collectValues(current: array[i], steps: steps, index: index + 1)
        }

        guard let dict = current as? [String: Any], let next = dict[step] else {
            return []
        }
        return collectValues(current: next, steps: steps, index: index + 1)
    }

    private func shouldApplyAilinyuQuotaConversion(baseURL: URL, config: RelayAccountBalanceConfig) -> Bool {
        guard let host = baseURL.host?.lowercased(),
              host.contains("open.ailinyu.de") else {
            return false
        }
        let endpoint = normalizedPath(config.endpointPath)
        return endpoint == "/api/user/self" && config.remainingJSONPath == "data.quota"
    }

    private func convertAilinyuQuotaToDisplayAmount(
        baseURL: URL,
        headers: [String: String],
        quota: Double
    ) async throws -> AilinyuDisplayAmount {
        let root = try await requestJSON(
            url: baseURL.appending(path: "/api/status"),
            headers: headers,
            method: "GET",
            bodyJSON: nil
        )
        guard let quotaPerUnit = numericValue(at: "data.quota_per_unit", in: root), quotaPerUnit > 0 else {
            throw ProviderError.invalidResponse("missing data.quota_per_unit")
        }
        let displayType = stringValue(at: "data.quota_display_type", in: root)?.uppercased() ?? "USD"
        let displayRate: Double
        let unit: String
        switch displayType {
        case "CNY":
            displayRate = numericValue(at: "data.usd_exchange_rate", in: root) ?? 1
            unit = "¥"
        case "CUSTOM":
            displayRate = numericValue(at: "data.custom_currency_exchange_rate", in: root) ?? 1
            unit = stringValue(at: "data.custom_currency_symbol", in: root) ?? "¤"
        case "TOKENS":
            displayRate = 1
            unit = "tokens"
        default:
            displayRate = 1
            unit = "$"
        }

        if displayType == "TOKENS" {
            return AilinyuDisplayAmount(
                remaining: quota,
                quotaPerUnit: quotaPerUnit,
                rate: 1,
                unit: unit,
                displayType: displayType
            )
        }

        let remaining = (quota / quotaPerUnit) * displayRate
        return AilinyuDisplayAmount(
            remaining: remaining,
            quotaPerUnit: quotaPerUnit,
            rate: displayRate,
            unit: unit,
            displayType: displayType
        )
    }

    private func stringValue(at path: String, in root: Any) -> String? {
        if let string = value(at: path, in: root) as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func coerceDouble(_ value: Any) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(trimmed)
        }
        return nil
    }

    private func coerceBool(_ value: Any) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.intValue != 0 }
        if let string = value as? String {
            switch string.lowercased() {
            case "true", "1", "yes", "ok", "success":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private func request<T: Decodable>(url: URL, bearerToken: String, type: T.Type) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("non-http response")
        }

        if http.statusCode == 401 {
            if let message = extractErrorMessage(from: data), !message.isEmpty {
                throw ProviderError.unauthorizedDetail(message)
            }
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("http \(http.statusCode)")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ProviderError.invalidResponse("decode failed for \(url.path)")
        }
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        guard let object = root as? [String: Any] else { return nil }
        if let message = object["message"] as? String {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let error = object["error"] as? String {
            return error.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let details = object["details"] as? String {
            return details.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

private struct AilinyuDisplayAmount {
    let remaining: Double
    let quotaPerUnit: Double
    let rate: Double
    let unit: String
    let displayType: String
}

private struct TokenChannelResult {
    let remaining: Double?
    let used: Double?
    let limit: Double?
    let unit: String
    let note: String
    let rawMeta: [String: String]
}

private struct AccountChannelResult {
    let remaining: Double?
    let used: Double?
    let limit: Double?
    let unit: String
    let note: String
    let rawMeta: [String: String]
}

struct OpenTokenUsageEnvelope: Decodable {
    struct TokenUsage: Decodable {
        let expiresAt: Int?
        let name: String
        let object: String?
        let totalAvailable: Double
        let totalGranted: Double
        let totalUsed: Double
        let unlimitedQuota: Bool

        enum CodingKeys: String, CodingKey {
            case expiresAt = "expires_at"
            case name
            case object
            case totalAvailable = "total_available"
            case totalGranted = "total_granted"
            case totalUsed = "total_used"
            case unlimitedQuota = "unlimited_quota"
        }
    }

    let code: Bool?
    let message: String?
    let data: TokenUsage
}

struct OpenBillingSubscription: Decodable {
    let object: String
    let hasPaymentMethod: Bool
    let softLimitUSD: Double
    let hardLimitUSD: Double
    let systemHardLimitUSD: Double
    let accessUntil: Int

    enum CodingKeys: String, CodingKey {
        case object
        case hasPaymentMethod = "has_payment_method"
        case softLimitUSD = "soft_limit_usd"
        case hardLimitUSD = "hard_limit_usd"
        case systemHardLimitUSD = "system_hard_limit_usd"
        case accessUntil = "access_until"
    }
}

struct OpenBillingUsage: Decodable {
    let object: String
    let totalUsage: Double

    enum CodingKeys: String, CodingKey {
        case object
        case totalUsage = "total_usage"
    }
}
