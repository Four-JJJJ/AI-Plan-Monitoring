import Foundation

final class KimiOfficialProvider: UsageProvider, @unchecked Sendable {
    private static let cache = KimiOfficialSnapshotCache()
    private static let gate = KimiOfficialFetchGate()

    private let cacheTTL: TimeInterval = 15
    private let refreshBuffer: TimeInterval = 5 * 60
    private let session: URLSession

    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared
    ) {
        self.descriptor = descriptor
        self.session = session
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        try await Self.gate.withPermit { [self] in
            if !forceRefresh,
               let cached = await Self.cache.snapshotIfFresh(for: descriptor.id, ttl: cacheTTL) {
                return cached
            }

            do {
                let snapshot = try await loadSnapshot()
                await Self.cache.store(snapshot, for: descriptor.id)
                return snapshot
            } catch {
                if let stale = await Self.cache.snapshotAny(for: descriptor.id) {
                    var fallback = stale
                    fallback.status = .warning
                    fallback.updatedAt = Date()
                    fallback.note = stale.note.isEmpty ? "cached fallback" : "\(stale.note) | cached"
                    return fallback
                }
                throw error
            }
        }
    }

    private func loadSnapshot() async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .kimi)
        switch official.sourceMode {
        case .api, .auto:
            return try await loadFromAPI()
        case .cli:
            throw ProviderError.unavailable("Kimi 官方来源当前仅支持 API 凭证发现")
        case .web:
            throw ProviderError.unavailable("Kimi 官方来源当前不支持网页 Cookie 检测")
        }
    }

    private func loadFromAPI() async throws -> UsageSnapshot {
        var credentials = try loadCredentials()
        if needsRefresh(credentials.expiresAt) {
            credentials = try await refresh(credentials: credentials)
        }

        do {
            return try await requestSnapshot(accessToken: credentials.accessToken)
        } catch let error as ProviderError {
            guard case .unauthorized = error else { throw error }
            credentials = try await refresh(credentials: credentials)
            return try await requestSnapshot(accessToken: credentials.accessToken)
        }
    }

    private func requestSnapshot(accessToken: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: URL(string: "https://api.kimi.com/coding/v1/usages")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AIPlanMonitor", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Kimi non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Kimi http \(http.statusCode)")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Kimi response decode failed")
        }
        return try Self.parseUsageSnapshot(
            root: root,
            descriptor: descriptor,
            sourceLabel: "API"
        )
    }

    private func loadCredentials() throws -> KimiOfficialCredentials {
        let candidates = resolveCredentialPaths()
        for path in candidates {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let auth = (json["auth"] as? [String: Any]) ?? json
            guard let accessToken = OfficialValueParser.string(auth["access_token"] ?? auth["accessToken"]),
                  !accessToken.isEmpty else {
                continue
            }
            return KimiOfficialCredentials(
                accessToken: accessToken,
                refreshToken: OfficialValueParser.string(auth["refresh_token"] ?? auth["refreshToken"]),
                expiresAt: parseExpiry(auth: auth),
                filePath: path
            )
        }

        let primary = candidates.first ?? "\(NSHomeDirectory())/.kimi/credentials/kimi-code.json"
        throw ProviderError.missingCredential(primary)
    }

    private func resolveCredentialPaths() -> [String] {
        let home = NSHomeDirectory()
        let explicit = [
            "\(home)/.kimi/credentials/kimi-code.json",
            "\(home)/.config/kimi/credentials/kimi-code.json",
            "\(home)/Library/Application Support/kimi/credentials/kimi-code.json",
            "\(home)/Library/Application Support/Kimi/credentials/kimi-code.json",
            "\(home)/.kimi/oauth/kimi-code.json",
            "\(home)/.kimi/credentials/oauth/kimi-code.json",
        ]

        var discovered: [String] = []
        if let enumerator = FileManager.default.enumerator(
            atPath: "\(home)/.kimi/credentials"
        ) {
            for case let item as String in enumerator {
                let lower = item.lowercased()
                guard lower.hasSuffix(".json"),
                      lower.contains("kimi"),
                      lower.contains("code") else {
                    continue
                }
                discovered.append("\(home)/.kimi/credentials/\(item)")
            }
        }

        return Array(NSOrderedSet(array: explicit + discovered)) as? [String] ?? (explicit + discovered)
    }

    private func parseExpiry(auth: [String: Any]) -> Date? {
        if let raw = OfficialValueParser.double(auth["expires_at"] ?? auth["expiresAt"] ?? auth["expiry_date"]) {
            return raw > 1_000_000_000_000
                ? Date(timeIntervalSince1970: raw / 1000)
                : Date(timeIntervalSince1970: raw)
        }
        if let raw = OfficialValueParser.string(auth["expires_at_iso"] ?? auth["expiresAtIso"]) {
            return OfficialValueParser.isoDate(raw)
        }
        return nil
    }

    private func needsRefresh(_ expiresAt: Date?) -> Bool {
        guard let expiresAt else { return false }
        return Date().addingTimeInterval(refreshBuffer) >= expiresAt
    }

    private func refresh(credentials: KimiOfficialCredentials) async throws -> KimiOfficialCredentials {
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            throw ProviderError.unauthorized
        }

        var request = URLRequest(url: URL(string: "https://auth.kimi.com/api/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "17e5f671-d194-4dfb-9706-5516cb48c098",
        ]
        request.httpBody = form
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Kimi refresh invalid response")
        }
        if http.statusCode == 400 || http.statusCode == 401 {
            throw ProviderError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Kimi refresh http \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = OfficialValueParser.string(json["access_token"]) else {
            throw ProviderError.invalidResponse("missing Kimi refresh access_token")
        }

        var updated = credentials
        updated.accessToken = accessToken
        updated.refreshToken = OfficialValueParser.string(json["refresh_token"]) ?? updated.refreshToken
        if let expiresIn = OfficialValueParser.double(json["expires_in"]) {
            updated.expiresAt = Date().addingTimeInterval(expiresIn)
        }
        persist(credentials: updated)
        return updated
    }

    private func persist(credentials: KimiOfficialCredentials) {
        let path = credentials.filePath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }
        var auth = (json["auth"] as? [String: Any]) ?? json
        auth["access_token"] = credentials.accessToken
        auth["refresh_token"] = credentials.refreshToken
        auth["expires_at"] = credentials.expiresAt.map { Int64($0.timeIntervalSince1970) }
        if json["auth"] != nil {
            json["auth"] = auth
        } else {
            json = auth
        }
        guard let encoded = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) else {
            return
        }
        try? encoded.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    internal static func parseUsageSnapshot(
        root: [String: Any],
        descriptor: ProviderDescriptor,
        sourceLabel: String
    ) throws -> UsageSnapshot {
        let membership = (root["user"] as? [String: Any])?["membership"] as? [String: Any]
        let plan = OfficialValueParser.string(membership?["level"] ?? membership?["tier"] ?? root["plan"]) ?? "unknown"
        let accountLabel = OfficialValueParser.string((root["user"] as? [String: Any])?["email"])

        var windows: [UsageQuotaWindow] = []
        if let limits = root["limits"] as? [Any] {
            for (index, value) in limits.enumerated() {
                guard let item = value as? [String: Any],
                      let window = parseLimitWindow(item: item, descriptor: descriptor, index: index) else {
                    continue
                }
                windows.append(window)
            }
        }

        var extras: [String: String] = ["planType": plan]
        let usageCandidates = aggregateUsageCandidates(from: root)
        for (index, usage) in usageCandidates.enumerated() {
            if let customWindow = parseOverallUsage(
                usage: usage,
                descriptor: descriptor,
                idSuffix: index == 0 ? "overall" : "overall-\(index)"
            ) {
                windows.append(customWindow)
            }
            if extras["overallUsed"] == nil,
               let used = OfficialValueParser.double(
                   usage["used_amount"]
                   ?? usage["usedAmount"]
                   ?? usage["usedCredits"]
                   ?? usage["used"]
                   ?? usage["consumed"]
               ) {
                extras["overallUsed"] = String(format: "%.2f", used)
            }
            if extras["overallLimit"] == nil,
               let limit = OfficialValueParser.double(
                   usage["quota_amount"]
                   ?? usage["quotaAmount"]
                   ?? usage["monthly_limit"]
                   ?? usage["total_limit"]
                   ?? usage["limit"]
                   ?? usage["total"]
               ) {
                extras["overallLimit"] = String(format: "%.2f", limit)
            }
        }

        if !windows.contains(where: { $0.kind == .weekly }),
           let fallbackWeekly = fallbackWeeklyWindow(from: root, descriptor: descriptor) {
            windows.append(fallbackWeekly)
        }

        guard !windows.isEmpty else {
            throw ProviderError.invalidResponse("missing Kimi usage windows")
        }

        windows.sort { lhs, rhs in
            metricRank(lhs.kind) == metricRank(rhs.kind)
                ? lhs.title < rhs.title
                : metricRank(lhs.kind) < metricRank(rhs.kind)
        }

        let remaining = windows.map(\.remainingPercent).min() ?? 0
        let note = windows
            .map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }
            .joined(separator: " | ")

        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "Plan \(plan) | \(note)",
            quotaWindows: windows,
            sourceLabel: sourceLabel,
            accountLabel: accountLabel,
            extras: extras,
            rawMeta: [:]
        )
    }

    private static func parseLimitWindow(item: [String: Any], descriptor: ProviderDescriptor, index: Int) -> UsageQuotaWindow? {
        let usage = (item["usage"] as? [String: Any]) ?? (item["detail"] as? [String: Any]) ?? item
        let window = (item["window"] as? [String: Any]) ?? [:]
        let kind = classifyWindow(item: item, window: window)
        let title: String
        switch kind {
        case .session:
            title = "5h"
        case .weekly:
            title = "Weekly"
        default:
            title = OfficialValueParser.string(item["name"] ?? item["title"]) ?? "Window \(index + 1)"
        }

        guard let remaining = OfficialValueParser.double(usage["remaining_amount"] ?? usage["remaining"] ?? usage["available"]),
              let limit = OfficialValueParser.double(usage["quota_amount"] ?? usage["limit"] ?? usage["total"]) else {
            return nil
        }
        let remainingPercent = percent(remaining: remaining, limit: limit)
        return UsageQuotaWindow(
            id: "\(descriptor.id)-\(kind.rawValue)-\(index)",
            title: title,
            remainingPercent: remainingPercent,
            usedPercent: max(0, 100 - remainingPercent),
            resetAt: parseResetAt(
                window["resets_at"],
                window["reset_at"],
                window["resetAt"],
                window["next_reset_at"],
                window["nextResetAt"],
                window["next_reset_time"],
                window["nextResetTime"],
                usage["resets_at"],
                usage["reset_at"],
                usage["resetAt"],
                usage["reset_time"],
                usage["resetTime"],
                usage["next_reset_at"],
                usage["nextResetAt"],
                item["resets_at"],
                item["reset_at"],
                item["resetAt"],
                item["next_reset_at"],
                item["nextResetAt"]
            ),
            kind: kind
        )
    }

    private static func parseOverallUsage(
        usage: [String: Any],
        descriptor: ProviderDescriptor,
        idSuffix: String
    ) -> UsageQuotaWindow? {
        let remaining = OfficialValueParser.double(
            usage["remaining_amount"]
            ?? usage["remainingAmount"]
            ?? usage["remaining"]
            ?? usage["available_amount"]
            ?? usage["availableAmount"]
            ?? usage["available"]
        )
        let used = OfficialValueParser.double(
            usage["used_amount"]
            ?? usage["usedAmount"]
            ?? usage["used"]
            ?? usage["consumed_amount"]
            ?? usage["consumedAmount"]
            ?? usage["consumed"]
            ?? usage["spent"]
        )
        guard let limit = OfficialValueParser.double(
            usage["quota_amount"]
            ?? usage["quotaAmount"]
            ?? usage["monthly_limit"]
            ?? usage["total_limit"]
            ?? usage["limit"]
            ?? usage["total"]
        ) else {
            return nil
        }
        let resolvedRemaining = remaining ?? used.map { max(0, limit - $0) }
        guard let resolvedRemaining else { return nil }
        let title = OfficialValueParser.string(usage["title"] ?? usage["name"]) ?? "Overall"
        let lower = title.lowercased()
        let kind: UsageQuotaKind = lower.contains("week") || lower.contains("周") ? .weekly : .custom
        let remainingPercent = percent(remaining: resolvedRemaining, limit: limit)
        return UsageQuotaWindow(
            id: "\(descriptor.id)-\(idSuffix)",
            title: kind == .weekly ? "Weekly" : title,
            remainingPercent: remainingPercent,
            usedPercent: max(0, 100 - remainingPercent),
            resetAt: parseResetAt(
                usage["resets_at"],
                usage["reset_at"],
                usage["resetAt"],
                usage["reset_time"],
                usage["resetTime"],
                usage["next_reset_at"],
                usage["nextResetAt"],
                usage["next_cycle_at"],
                usage["nextCycleAt"],
                usage["quota_reset_at"],
                usage["quotaResetAt"]
            ),
            kind: kind
        )
    }

    private static func aggregateUsageCandidates(from root: [String: Any]) -> [[String: Any]] {
        var output: [[String: Any]] = []

        func collect(from container: [String: Any], keys: [String]) {
            for key in keys {
                if let map = container[key] as? [String: Any] {
                    output.append(map)
                }
            }
        }

        collect(from: root, keys: ["usage", "overall_usage", "overallUsage", "quota", "summary", "billing"])
        if let data = root["data"] as? [String: Any] {
            collect(from: data, keys: ["usage", "overall_usage", "overallUsage", "quota", "summary", "billing"])
        }
        if let result = root["result"] as? [String: Any] {
            collect(from: result, keys: ["usage", "overall_usage", "overallUsage", "quota", "summary", "billing"])
        }

        if output.isEmpty, let map = root["usage"] as? [String: Any] {
            output.append(map)
        }

        var seen = Set<String>()
        return output.filter { item in
            let signature = [
                OfficialValueParser.string(item["title"] ?? item["name"]) ?? "",
                OfficialValueParser.string(item["remaining_amount"] ?? item["remaining"] ?? item["available"]) ?? "",
                OfficialValueParser.string(item["quota_amount"] ?? item["monthly_limit"] ?? item["limit"] ?? item["total"]) ?? ""
            ].joined(separator: "|")
            if seen.contains(signature) { return false }
            seen.insert(signature)
            return true
        }
    }

    private static func fallbackWeeklyWindow(from root: [String: Any], descriptor: ProviderDescriptor) -> UsageQuotaWindow? {
        let fallbackSources: [[String: Any]] = [
            root,
            root["data"] as? [String: Any] ?? [:],
            root["result"] as? [String: Any] ?? [:]
        ]

        for source in fallbackSources {
            let remaining = OfficialValueParser.double(
                source["weekly_remaining"]
                ?? source["weeklyRemaining"]
                ?? source["remaining_amount"]
                ?? source["remaining"]
                ?? source["available"]
            )
            let used = OfficialValueParser.double(
                source["weekly_used"]
                ?? source["weeklyUsed"]
                ?? source["used_amount"]
                ?? source["used"]
            )
            guard let limit = OfficialValueParser.double(
                source["weekly_limit"]
                ?? source["weeklyLimit"]
                ?? source["quota_amount"]
                ?? source["limit"]
                ?? source["total"]
            ) else {
                continue
            }
            let resolvedRemaining = remaining ?? used.map { max(0, limit - $0) }
            guard let resolvedRemaining else { continue }
            let remainingPercent = percent(remaining: resolvedRemaining, limit: limit)
            return UsageQuotaWindow(
                id: "\(descriptor.id)-weekly-fallback",
                title: "Weekly",
                remainingPercent: remainingPercent,
                usedPercent: max(0, 100 - remainingPercent),
                resetAt: parseResetAt(
                    source["weekly_reset_at"],
                    source["weeklyResetAt"],
                    source["reset_at"],
                    source["resetAt"],
                    source["next_reset_at"],
                    source["nextResetAt"]
                ),
                kind: .weekly
            )
        }
        return nil
    }

    private static func classifyWindow(item: [String: Any], window: [String: Any]) -> UsageQuotaKind {
        let title = (OfficialValueParser.string(item["name"] ?? item["title"]) ?? "").lowercased()
        if title.contains("week") || title.contains("周") {
            return .weekly
        }
        if let duration = OfficialValueParser.int(window["duration"]),
           let timeUnit = OfficialValueParser.string(window["time_unit"] ?? window["timeUnit"])?.lowercased() {
            if duration == 300 && timeUnit.contains("minute") {
                return .session
            }
            if duration >= 7 && timeUnit.contains("day") {
                return .weekly
            }
        }
        return .custom
    }

    private static func percent(remaining: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        return min(100, max(0, remaining / limit * 100))
    }

    private static func parseResetAt(_ candidates: Any?...) -> Date? {
        for candidate in candidates {
            if let rawString = OfficialValueParser.string(candidate) {
                if let date = OfficialValueParser.isoDate(rawString) {
                    return date
                }
                if let rawNumber = Double(rawString) {
                    return normalizedEpochDate(rawNumber)
                }
            }
            if let rawNumber = OfficialValueParser.double(candidate) {
                return normalizedEpochDate(rawNumber)
            }
        }
        return nil
    }

    private static func normalizedEpochDate(_ raw: Double) -> Date {
        if raw > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: raw / 1000)
        }
        return Date(timeIntervalSince1970: raw)
    }

    private static func metricRank(_ kind: UsageQuotaKind) -> Int {
        switch kind {
        case .session: return 0
        case .weekly: return 1
        default: return 2
        }
    }
}

private struct KimiOfficialCredentials {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var filePath: String
}

private actor KimiOfficialSnapshotCache {
    private var storage: [String: UsageSnapshot] = [:]

    func snapshotIfFresh(for key: String, ttl: TimeInterval) -> UsageSnapshot? {
        guard let snapshot = storage[key] else { return nil }
        guard Date().timeIntervalSince(snapshot.updatedAt) <= ttl else { return nil }
        return snapshot
    }

    func snapshotAny(for key: String) -> UsageSnapshot? {
        storage[key]
    }

    func store(_ snapshot: UsageSnapshot, for key: String) {
        storage[key] = snapshot
    }
}

private actor KimiOfficialFetchGate {
    func withPermit<T>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await operation()
    }
}
