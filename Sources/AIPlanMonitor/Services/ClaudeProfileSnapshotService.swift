import Foundation

struct ClaudeProfileSnapshotResult {
    var snapshot: UsageSnapshot
    var refreshedCredentialsJSON: String?
}

actor ClaudeProfileSnapshotService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSnapshot(
        profile: ClaudeAccountProfile,
        descriptor: ProviderDescriptor
    ) async throws -> ClaudeProfileSnapshotResult {
        var credentialsJSON = try ClaudeAccountProfileStore.resolvedCredentialsJSON(for: profile)
        var parsed = try ClaudeAccountProfileStore.parseCredentialsJSON(credentialsJSON)

        if needsRefresh(expiresAtMs: parsed.expiresAtMs), parsed.refreshToken != nil {
            if let refreshed = try await refreshCredentials(rawJSON: credentialsJSON, payload: parsed) {
                credentialsJSON = refreshed.rawJSON
                parsed = refreshed.payload
            }
        }

        let root = try await requestOAuthUsage(accessToken: parsed.accessToken)
        var snapshot = try ClaudeProvider.parseClaudeSnapshot(
            root: root,
            descriptor: descriptor,
            sourceLabel: "Profile",
            accountLabel: parsed.accountEmail ?? profile.accountEmail,
            planHint: parsed.subscriptionType
        )

        if let accountId = parsed.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountId.isEmpty {
            snapshot.rawMeta["claude.accountId"] = accountId
        }
        if let email = (parsed.accountEmail ?? profile.accountEmail)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty {
            snapshot.accountLabel = email
            snapshot.rawMeta["claude.accountLabel"] = email
        }
        snapshot.rawMeta["claude.credentialFingerprint"] = parsed.credentialFingerprint
        if let configDir = profile.configDir?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configDir.isEmpty {
            snapshot.rawMeta["claude.configDir"] = configDir
        }

        let refreshedCredentialsJSON = credentialsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            != (profile.credentialsJSON ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            ? credentialsJSON
            : nil

        return ClaudeProfileSnapshotResult(
            snapshot: snapshot,
            refreshedCredentialsJSON: refreshedCredentialsJSON
        )
    }

    private func requestOAuthUsage(accessToken: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("AIPlanMonitor", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("http \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("oauth usage decode failed")
        }
        return json
    }

    private func needsRefresh(expiresAtMs: Double?) -> Bool {
        guard let expiresAtMs else { return false }
        let nowMs = Date().timeIntervalSince1970 * 1000
        return nowMs + 5 * 60 * 1000 >= expiresAtMs
    }

    private func refreshCredentials(
        rawJSON: String,
        payload: ClaudeParsedCredentialsPayload
    ) async throws -> (payload: ClaudeParsedCredentialsPayload, rawJSON: String)? {
        guard let refreshToken = payload.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !refreshToken.isEmpty else {
            return nil
        }

        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
            "scope": "user:profile user:inference user:sessions:claude_code user:mcp_servers"
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("refresh invalid response")
        }
        if http.statusCode == 400 || http.statusCode == 401 {
            throw ProviderError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("refresh http \(http.statusCode)")
        }
        guard let refreshRoot = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = OfficialValueParser.string(refreshRoot["access_token"]),
              !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderError.invalidResponse("missing refresh access_token")
        }

        guard let sourceData = rawJSON.data(using: .utf8),
              var root = (try? JSONSerialization.jsonObject(with: sourceData)) as? [String: Any] else {
            throw ProviderError.invalidResponse("invalid credentials json")
        }

        var oauth = (root["claudeAiOauth"] as? [String: Any]) ?? root
        oauth["accessToken"] = accessToken
        oauth["refreshToken"] = OfficialValueParser.string(refreshRoot["refresh_token"]) ?? payload.refreshToken
        if let expiresIn = OfficialValueParser.double(refreshRoot["expires_in"]) {
            oauth["expiresAt"] = Date().timeIntervalSince1970 * 1000 + expiresIn * 1000
        }
        if let subscriptionType = payload.subscriptionType {
            oauth["subscriptionType"] = subscriptionType
        }
        if root["claudeAiOauth"] != nil {
            root["claudeAiOauth"] = oauth
        } else {
            root = oauth
        }

        guard let encoded = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]),
              let updatedRawJSON = String(data: encoded, encoding: .utf8) else {
            throw ProviderError.invalidResponse("invalid refreshed credentials")
        }

        let updatedPayload = try ClaudeAccountProfileStore.parseCredentialsJSON(updatedRawJSON)
        return (updatedPayload, updatedRawJSON)
    }
}
