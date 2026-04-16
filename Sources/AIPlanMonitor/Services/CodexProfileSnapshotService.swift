import Foundation

actor CodexProfileSnapshotService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSnapshot(
        profile: CodexAccountProfile,
        descriptor: ProviderDescriptor
    ) async throws -> UsageSnapshot {
        let payload = try CodexAccountProfileStore.parseAuthJSON(profile.authJSON)
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

        var snapshot = try CodexProvider.parseUsageSnapshot(
            data: data,
            response: http,
            descriptor: descriptor,
            sourceLabel: "Profile",
            accountLabel: profile.accountEmail
        )

        if let accountId = payload.accountId, !accountId.isEmpty {
            snapshot.rawMeta["codex.accountId"] = accountId
        }
        if let email = payload.accountEmail, !email.isEmpty {
            snapshot.rawMeta["codex.accountLabel"] = email
            snapshot.accountLabel = email
        }
        snapshot.rawMeta["codex.credentialFingerprint"] = payload.credentialFingerprint

        return snapshot
    }
}
