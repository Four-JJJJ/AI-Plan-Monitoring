import Foundation

struct CodexProfileSnapshotResult {
    var snapshot: UsageSnapshot
    var refreshedAuthJSON: String?
}

actor CodexProfileSnapshotService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSnapshot(
        profile: CodexAccountProfile,
        descriptor: ProviderDescriptor
    ) async throws -> CodexProfileSnapshotResult {
        var authJSON = profile.authJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        var payload = try CodexAccountProfileStore.parseAuthJSON(authJSON)
        var refreshedAuthJSON: String?
        var usageData: Data
        var usageResponse: HTTPURLResponse

        do {
            (usageData, usageResponse) = try await requestUsage(payload: payload)
        } catch let error as ProviderError {
            guard case .unauthorized = error,
                  let refreshed = try await refreshAuthJSONIfNeeded(rawAuthJSON: authJSON, payload: payload) else {
                throw error
            }
            authJSON = refreshed.rawAuthJSON
            payload = refreshed.payload
            if authJSON != profile.authJSON.trimmingCharacters(in: .whitespacesAndNewlines) {
                refreshedAuthJSON = authJSON
            }
            (usageData, usageResponse) = try await requestUsage(payload: payload)
        }

        var snapshot = try CodexProvider.parseUsageSnapshot(
            data: usageData,
            response: usageResponse,
            descriptor: descriptor,
            sourceLabel: "Profile",
            accountLabel: profile.accountEmail
        )

        if let accountId = payload.accountId, !accountId.isEmpty {
            snapshot.rawMeta["codex.accountId"] = accountId
            snapshot.rawMeta["codex.teamId"] = accountId
        }
        if let subject = payload.accountSubject, !subject.isEmpty {
            snapshot.rawMeta["codex.subject"] = subject
        }
        if let email = payload.accountEmail, !email.isEmpty {
            snapshot.rawMeta["codex.accountLabel"] = email
            snapshot.accountLabel = email
        }
        snapshot.rawMeta["codex.credentialFingerprint"] = payload.credentialFingerprint
        let identity = CodexIdentity.from(payload: payload)
        snapshot.rawMeta["codex.tenantKey"] = identity.tenantKey
        snapshot.rawMeta["codex.principalKey"] = identity.principalKey
        snapshot.rawMeta["codex.identityKey"] = identity.identityKey

        return CodexProfileSnapshotResult(
            snapshot: snapshot,
            refreshedAuthJSON: refreshedAuthJSON
        )
    }

    private func requestUsage(payload: CodexParsedAuthPayload) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AIPlanMonitor", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(payload.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountId = payload.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

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
        return (data, http)
    }

    private func refreshAuthJSONIfNeeded(
        rawAuthJSON: String,
        payload: CodexParsedAuthPayload
    ) async throws -> (payload: CodexParsedAuthPayload, rawAuthJSON: String)? {
        guard let refreshToken = payload.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !refreshToken.isEmpty else {
            return nil
        }

        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=refresh_token&client_id=app_EMoamEEZ73f0CkXaXp7hrann&refresh_token=\(refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? refreshToken)"
            .data(using: .utf8)

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
              !accessToken.isEmpty else {
            throw ProviderError.invalidResponse("missing refresh access_token")
        }

        guard let sourceData = rawAuthJSON.data(using: .utf8),
              var root = (try? JSONSerialization.jsonObject(with: sourceData)) as? [String: Any] else {
            throw ProviderError.invalidResponse("invalid auth json")
        }

        let resolvedRefreshToken = OfficialValueParser.string(refreshRoot["refresh_token"]) ?? payload.refreshToken
        let resolvedIDToken = OfficialValueParser.string(refreshRoot["id_token"]) ?? payload.idToken
        let resolvedAccountID = OfficialValueParser.string(refreshRoot["account_id"] ?? refreshRoot["accountId"]) ?? payload.accountId

        var tokens = (root["tokens"] as? [String: Any]) ?? root
        tokens["access_token"] = accessToken
        tokens["refresh_token"] = resolvedRefreshToken
        tokens["id_token"] = resolvedIDToken
        tokens["account_id"] = resolvedAccountID
        if root["tokens"] != nil {
            root["tokens"] = tokens
        } else {
            root = tokens
        }
        root["last_refresh"] = ISO8601DateFormatter().string(from: Date())

        guard let encoded = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
              let updatedRawAuthJSON = String(data: encoded, encoding: .utf8) else {
            throw ProviderError.invalidResponse("invalid refreshed auth json")
        }

        let refreshedPayload = try CodexAccountProfileStore.parseAuthJSON(updatedRawAuthJSON)
        return (payload: refreshedPayload, rawAuthJSON: updatedRawAuthJSON)
    }
}
