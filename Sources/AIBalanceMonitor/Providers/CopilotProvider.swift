import Foundation

final class CopilotProvider: UsageProvider, @unchecked Sendable {
    private let session: URLSession
    let descriptor: ProviderDescriptor

    init(descriptor: ProviderDescriptor, session: URLSession = .shared) {
        self.descriptor = descriptor
        self.session = session
    }

    func fetch() async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .copilot)
        guard official.sourceMode == .auto || official.sourceMode == .api else {
            throw ProviderError.unavailable("Copilot 官方来源当前仅支持 API 检测")
        }

        let token = try resolveToken()
        var request = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/user")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Copilot non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Copilot http \(http.statusCode)")
        }
        return try Self.parseSnapshot(data: data, descriptor: descriptor)
    }

    private func resolveToken() throws -> String {
        let env = ProcessInfo.processInfo.environment
        for key in ["GITHUB_TOKEN", "GH_TOKEN", "COPILOT_AUTH_TOKEN"] {
            if let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        if let value = SecurityCredentialReader.readGenericPassword(service: "gh:github.com"),
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let result = ShellCommand.run(executable: "/usr/bin/env", arguments: ["gh", "auth", "token"], timeout: 8),
           result.status == 0 {
            let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        throw ProviderError.missingCredential("gh auth token")
    }

    internal static func parseSnapshot(data: Data, descriptor: ProviderDescriptor) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Copilot usage decode failed")
        }

        let plan = OfficialValueParser.string(root["copilot_plan"] ?? root["access_type_sku"]) ?? "unknown"
        let paidReset = OfficialValueParser.isoDate(OfficialValueParser.string(root["quota_reset_date"] ?? root["quota_reset_date_utc"]))
        let freeReset = parseDateOnly(OfficialValueParser.string(root["limited_user_reset_date"]))
        let snapshots = root["quota_snapshots"] as? [String: Any]
        let limitedUser = root["limited_user_quotas"] as? [String: Any]
        let monthly = root["monthly_quotas"] as? [String: Any]

        var windows: [UsageQuotaWindow] = []
        if let premium = snapshots?["premium_interactions"] as? [String: Any],
           let remainingPercent = OfficialValueParser.double(premium["percent_remaining"]) {
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-premium",
                    title: "Premium",
                    remainingPercent: remainingPercent,
                    usedPercent: max(0, 100 - remainingPercent),
                    resetAt: paidReset,
                    kind: .custom
                )
            )
        }
        if let chat = snapshots?["chat"] as? [String: Any],
           let remainingPercent = OfficialValueParser.double(chat["percent_remaining"]) {
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-chat",
                    title: "Chat",
                    remainingPercent: remainingPercent,
                    usedPercent: max(0, 100 - remainingPercent),
                    resetAt: paidReset,
                    kind: .custom
                )
            )
        }
        if let remaining = OfficialValueParser.double(limitedUser?["chat"]),
           let total = OfficialValueParser.double(monthly?["chat"]), total > 0 {
            let percent = remaining / total * 100
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-chat-free",
                    title: "Chat",
                    remainingPercent: percent,
                    usedPercent: max(0, 100 - percent),
                    resetAt: freeReset,
                    kind: .custom
                )
            )
        }
        if let remaining = OfficialValueParser.double(limitedUser?["completions"]),
           let total = OfficialValueParser.double(monthly?["completions"]), total > 0 {
            let percent = remaining / total * 100
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-completions",
                    title: "Completions",
                    remainingPercent: percent,
                    usedPercent: max(0, 100 - percent),
                    resetAt: freeReset,
                    kind: .custom
                )
            )
        }

        guard !windows.isEmpty else {
            throw ProviderError.invalidResponse("missing Copilot quota windows")
        }

        let remaining = windows.map(\.remainingPercent).min() ?? 0
        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "Plan \(plan) | " + windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }.joined(separator: " | "),
            quotaWindows: windows,
            sourceLabel: "API",
            accountLabel: nil,
            extras: ["planType": plan],
            rawMeta: [:]
        )
    }

    private static func parseDateOnly(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }
}

