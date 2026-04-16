import Foundation

final class GeminiProvider: UsageProvider, @unchecked Sendable {
    private static let cache = GeminiSnapshotCache()
    private static let gate = GeminiFetchGate()

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
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .gemini)
        switch official.sourceMode {
        case .api, .auto:
            return try await loadFromAPI()
        case .cli:
            throw ProviderError.unavailable("Gemini 官方来源当前仅支持 API 凭证发现")
        case .web:
            throw ProviderError.unavailable("Gemini 官方来源当前不支持网页 Cookie 检测")
        }
    }

    private func loadFromAPI() async throws -> UsageSnapshot {
        let settings = try loadSettings()
        switch settings.authType {
        case "api-key":
            throw ProviderError.unavailable("Gemini API key 模式无法稳定获取官方订阅配额")
        case "vertex-ai":
            throw ProviderError.unavailable("Gemini Vertex AI 模式不属于个人官方订阅配额")
        default:
            break
        }

        var credentials = try loadCredentials()
        if needsRefresh(credentials.expiresAt) {
            credentials = try await refresh(credentials: credentials)
        }

        do {
            return try await requestSnapshot(accessToken: credentials.accessToken, settings: settings, credentials: credentials)
        } catch let error as ProviderError {
            guard case .unauthorized = error else { throw error }
            credentials = try await refresh(credentials: credentials)
            return try await requestSnapshot(accessToken: credentials.accessToken, settings: settings, credentials: credentials)
        }
    }

    private func requestSnapshot(
        accessToken: String,
        settings: GeminiSettings,
        credentials: GeminiCredentials
    ) async throws -> UsageSnapshot {
        let codeAssist = try await requestJSON(
            url: URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!,
            accessToken: accessToken,
            body: [:]
        )
        let quotaRoot = try await requestJSON(
            url: URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!,
            accessToken: accessToken,
            body: [:]
        )

        var projectLabel = settings.selectedProject
        if let projectId = projectLabel,
           let resolved = try? await resolveProjectName(accessToken: accessToken, projectID: projectId) {
            projectLabel = resolved
        }

        return try Self.parseQuotaSnapshot(
            root: quotaRoot,
            codeAssistRoot: codeAssist,
            descriptor: descriptor,
            sourceLabel: "API",
            accountLabel: credentials.accountLabel,
            projectLabel: projectLabel
        )
    }

    private func loadSettings() throws -> GeminiSettings {
        let path = "\(NSHomeDirectory())/.gemini/settings.json"
        guard FileManager.default.fileExists(atPath: path) else {
            throw ProviderError.missingCredential(path)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Gemini settings decode failed")
        }
        return GeminiSettings(
            authType: OfficialValueParser.string(json["selectedAuthType"] ?? json["authType"] ?? json["auth_type"]) ?? "oauth-personal",
            selectedProject: OfficialValueParser.string(json["selectedProject"] ?? json["projectId"] ?? json["project_id"])
        )
    }

    private func loadCredentials() throws -> GeminiCredentials {
        let path = "\(NSHomeDirectory())/.gemini/oauth_creds.json"
        guard FileManager.default.fileExists(atPath: path) else {
            throw ProviderError.missingCredential(path)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Gemini oauth credentials decode failed")
        }
        guard let accessToken = OfficialValueParser.string(json["access_token"] ?? json["accessToken"]),
              !accessToken.isEmpty else {
            throw ProviderError.invalidResponse("missing Gemini access_token")
        }
        return GeminiCredentials(
            accessToken: accessToken,
            refreshToken: OfficialValueParser.string(json["refresh_token"] ?? json["refreshToken"]),
            expiresAt: parseExpiry(json: json),
            idToken: OfficialValueParser.string(json["id_token"] ?? json["idToken"]),
            filePath: path
        )
    }

    private func parseExpiry(json: [String: Any]) -> Date? {
        if let raw = OfficialValueParser.double(json["expiry_date"] ?? json["expiryDate"]) {
            return raw > 1_000_000_000_000
                ? Date(timeIntervalSince1970: raw / 1000)
                : Date(timeIntervalSince1970: raw)
        }
        if let raw = OfficialValueParser.string(json["expires_at"] ?? json["expiresAt"]) {
            return OfficialValueParser.isoDate(raw)
        }
        return nil
    }

    private func needsRefresh(_ expiresAt: Date?) -> Bool {
        guard let expiresAt else { return false }
        return Date().addingTimeInterval(refreshBuffer) >= expiresAt
    }

    private func refresh(credentials: GeminiCredentials) async throws -> GeminiCredentials {
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            throw ProviderError.unauthorized
        }
        guard let client = resolveClientSecrets() else {
            throw ProviderError.unavailable("未找到 Gemini CLI OAuth client 配置，无法刷新令牌")
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let form = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": client.id,
            "client_secret": client.secret,
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
            throw ProviderError.invalidResponse("Gemini refresh invalid response")
        }
        if http.statusCode == 400 || http.statusCode == 401 {
            throw ProviderError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Gemini refresh http \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = OfficialValueParser.string(json["access_token"]) else {
            throw ProviderError.invalidResponse("missing Gemini refresh access_token")
        }

        var updated = credentials
        updated.accessToken = accessToken
        updated.idToken = OfficialValueParser.string(json["id_token"]) ?? updated.idToken
        if let expiresIn = OfficialValueParser.double(json["expires_in"]) {
            updated.expiresAt = Date().addingTimeInterval(expiresIn)
        }
        persist(credentials: updated)
        return updated
    }

    private func resolveClientSecrets() -> (id: String, secret: String)? {
        guard let geminiPath = ShellCommand.run(executable: "/usr/bin/which", arguments: ["gemini"], timeout: 5)?.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !geminiPath.isEmpty else {
            return nil
        }

        let binaryURL = URL(fileURLWithPath: geminiPath).resolvingSymlinksInPath()
        let candidates = [
            binaryURL.deletingLastPathComponent().appendingPathComponent("../lib/auth/oauth2.js").standardizedFileURL.path,
            binaryURL.deletingLastPathComponent().appendingPathComponent("../dist/auth/oauth2.js").standardizedFileURL.path,
            binaryURL.deletingLastPathComponent().appendingPathComponent("../build/auth/oauth2.js").standardizedFileURL.path,
            binaryURL.deletingLastPathComponent().appendingPathComponent("oauth2.js").standardizedFileURL.path,
        ]

        for path in candidates {
            guard FileManager.default.fileExists(atPath: path),
                  let source = try? String(contentsOfFile: path, encoding: .utf8),
                  let clientID = firstMatch(in: source, pattern: #"client[_-]?id["']?\s*[:=]\s*["']([^"']+)["']"#),
                  let clientSecret = firstMatch(in: source, pattern: #"client[_-]?secret["']?\s*[:=]\s*["']([^"']+)["']"#) else {
                continue
            }
            return (clientID, clientSecret)
        }

        return nil
    }

    private func firstMatch(in source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: source.utf16.count)
        guard let match = regex.firstMatch(in: source, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: source) else {
            return nil
        }
        let value = String(source[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func persist(credentials: GeminiCredentials) {
        let path = credentials.filePath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }
        json["access_token"] = credentials.accessToken
        json["refresh_token"] = credentials.refreshToken
        json["id_token"] = credentials.idToken
        json["expiry_date"] = credentials.expiresAt.map { Int64($0.timeIntervalSince1970 * 1000) }
        guard let encoded = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) else {
            return
        }
        try? encoded.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func requestJSON(
        url: URL,
        accessToken: String,
        body: [String: Any]
    ) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("AIPlanMonitor", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Gemini non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Gemini http \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Gemini response decode failed")
        }
        return json
    }

    private func resolveProjectName(accessToken: String, projectID: String) async throws -> String {
        guard let url = URL(string: "https://cloudresourcemanager.googleapis.com/v1/projects/\(projectID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? projectID)") else {
            return projectID
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AIPlanMonitor", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return projectID
        }
        return OfficialValueParser.string(json["name"] ?? json["projectName"]) ?? projectID
    }

    internal static func parseQuotaSnapshot(
        root: [String: Any],
        codeAssistRoot: [String: Any],
        descriptor: ProviderDescriptor,
        sourceLabel: String,
        accountLabel: String?,
        projectLabel: String?
    ) throws -> UsageSnapshot {
        let plan = parsePlan(from: codeAssistRoot) ?? "unknown"
        let quotas = extractQuotaEntries(from: root)
        guard !quotas.isEmpty else {
            throw ProviderError.invalidResponse("missing Gemini quota entries")
        }

        var grouped: [String: GeminiQuotaEntry] = [:]
        for entry in quotas {
            let key = entry.groupKey
            if let current = grouped[key] {
                if entry.remainingPercent < current.remainingPercent {
                    grouped[key] = entry
                }
            } else {
                grouped[key] = entry
            }
        }

        let sorted = grouped.values.sorted { lhs, rhs in
            lhs.sortRank == rhs.sortRank ? lhs.title < rhs.title : lhs.sortRank < rhs.sortRank
        }

        let windows = sorted.map { entry in
            UsageQuotaWindow(
                id: "\(descriptor.id)-\(entry.groupKey)",
                title: entry.title,
                remainingPercent: entry.remainingPercent,
                usedPercent: entry.usedPercent,
                resetAt: entry.resetAt,
                kind: .custom
            )
        }

        let remaining = windows.map(\.remainingPercent).min() ?? 0
        var extras: [String: String] = ["planType": plan]
        if let projectLabel, !projectLabel.isEmpty {
            extras["project"] = projectLabel
        }

        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: buildNote(plan: plan, windows: windows, projectLabel: projectLabel),
            quotaWindows: windows,
            sourceLabel: sourceLabel,
            accountLabel: accountLabel,
            extras: extras,
            rawMeta: [:]
        )
    }

    private static func parsePlan(from root: [String: Any]) -> String? {
        let raw = OfficialValueParser.string(root["tierId"] ?? root["tier"] ?? root["plan"] ?? root["codeAssistTier"])
        guard let raw else { return nil }
        switch raw.lowercased() {
        case let value where value.contains("pro"):
            return "pro"
        case let value where value.contains("standard"):
            return "standard"
        case let value where value.contains("free"):
            return "free"
        default:
            return raw
        }
    }

    private static func extractQuotaEntries(from root: [String: Any]) -> [GeminiQuotaEntry] {
        let keys = ["quotaInfos", "quota_infos", "quotas", "modelQuotas", "quotaInfo"]
        var entries: [GeminiQuotaEntry] = []

        for key in keys {
            guard let items = root[key] as? [Any] else { continue }
            for item in items {
                if let entry = parseQuotaEntry(item) {
                    entries.append(entry)
                }
            }
        }

        if entries.isEmpty {
            for (_, value) in root {
                if let items = value as? [Any] {
                    for item in items {
                        if let entry = parseQuotaEntry(item) {
                            entries.append(entry)
                        }
                    }
                }
            }
        }

        return entries
    }

    private static func parseQuotaEntry(_ value: Any) -> GeminiQuotaEntry? {
        guard let item = value as? [String: Any] else { return nil }
        let title = OfficialValueParser.string(item["displayName"] ?? item["modelName"] ?? item["quotaId"] ?? item["name"] ?? item["id"]) ?? "Quota"
        let lower = title.lowercased()
        let groupKey = lower.contains("flash") ? "flash" : "pro"
        let normalizedTitle = lower.contains("flash") ? "Flash" : "Pro"

        let candidateDictionaries = [
            item,
            item["usage"] as? [String: Any],
            item["quota"] as? [String: Any],
            item["window"] as? [String: Any],
            item["bucket"] as? [String: Any],
        ].compactMap { $0 }

        var usedPercent: Double?
        var resetAt: Date?
        for dict in candidateDictionaries {
            usedPercent = usedPercent ?? parseUsedPercent(dict: dict)
            resetAt = resetAt ?? parseResetAt(dict: dict)
        }

        guard let usedPercent else { return nil }
        return GeminiQuotaEntry(
            title: normalizedTitle,
            groupKey: groupKey,
            usedPercent: min(100, max(0, usedPercent)),
            remainingPercent: max(0, 100 - usedPercent),
            resetAt: resetAt,
            sortRank: groupKey == "pro" ? 0 : 1
        )
    }

    private static func parseUsedPercent(dict: [String: Any]) -> Double? {
        let keys = ["utilization", "usedPercent", "used_percent", "percentage", "percentUsed", "percent", "usageRatio"]
        for key in keys {
            guard let value = OfficialValueParser.double(dict[key]) else { continue }
            return value <= 1 ? value * 100 : value
        }
        return nil
    }

    private static func parseResetAt(dict: [String: Any]) -> Date? {
        if let raw = OfficialValueParser.string(dict["resetsAt"] ?? dict["resetAt"] ?? dict["reset_at"] ?? dict["nextResetAt"]) {
            return OfficialValueParser.isoDate(raw) ?? OfficialValueParser.epochDate(seconds: raw)
        }
        return OfficialValueParser.epochDate(seconds: dict["reset_at"])
    }

    private static func buildNote(plan: String, windows: [UsageQuotaWindow], projectLabel: String?) -> String {
        let details = windows
            .map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }
            .joined(separator: " | ")
        if let projectLabel, !projectLabel.isEmpty {
            return "Plan \(plan) | \(projectLabel) | \(details)"
        }
        return "Plan \(plan) | \(details)"
    }
}

private struct GeminiSettings {
    var authType: String
    var selectedProject: String?
}

private struct GeminiCredentials {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var idToken: String?
    var filePath: String

    var accountLabel: String? {
        guard let idToken else { return nil }
        return decodeJWTEmail(idToken)
    }

    private func decodeJWTEmail(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return OfficialValueParser.string(json["email"])
    }
}

private struct GeminiQuotaEntry {
    let title: String
    let groupKey: String
    let usedPercent: Double
    let remainingPercent: Double
    let resetAt: Date?
    let sortRank: Int
}

private actor GeminiSnapshotCache {
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

private actor GeminiFetchGate {
    func withPermit<T>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await operation()
    }
}
