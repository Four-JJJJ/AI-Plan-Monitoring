import Foundation

final class WindsurfProvider: UsageProvider, @unchecked Sendable {
    private let session: URLSession
    let descriptor: ProviderDescriptor

    init(descriptor: ProviderDescriptor, session: URLSession = .shared) {
        self.descriptor = descriptor
        self.session = session
    }

    func fetch() async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .windsurf)
        guard official.sourceMode == .auto || official.sourceMode == .api else {
            throw ProviderError.unavailable("Windsurf 官方来源当前仅支持 API 检测")
        }

        let variants = [
            (ideName: "windsurf", dbPath: "\(NSHomeDirectory())/Library/Application Support/Windsurf/User/globalStorage/state.vscdb"),
            (ideName: "windsurf-next", dbPath: "\(NSHomeDirectory())/Library/Application Support/Windsurf - Next/User/globalStorage/state.vscdb"),
        ]

        var sawAuthFailure = false
        for variant in variants {
            guard let raw = SQLiteShell.singleValue(
                databasePath: variant.dbPath,
                query: "SELECT value FROM ItemTable WHERE key = 'windsurfAuthStatus' LIMIT 1"
            ), !raw.isEmpty,
                  let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let apiKey = OfficialValueParser.string(json["apiKey"]) else {
                continue
            }
            do {
                return try await requestSnapshot(apiKey: apiKey, ideName: variant.ideName)
            } catch let error as ProviderError {
                if case .unauthorized = error {
                    sawAuthFailure = true
                    continue
                }
                throw error
            }
        }
        if sawAuthFailure {
            throw ProviderError.unauthorized
        }
        throw ProviderError.missingCredential("windsurfAuthStatus")
    }

    private func requestSnapshot(apiKey: String, ideName: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: URL(string: "https://server.self-serve.windsurf.com/exa.seat_management_pb.SeatManagementService/GetUserStatus")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "metadata": [
                "apiKey": apiKey,
                "ideName": ideName,
                "ideVersion": "1.108.2",
                "extensionName": ideName,
                "extensionVersion": "1.108.2",
                "locale": "en",
            ]
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Windsurf non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Windsurf http \(http.statusCode)")
        }
        return try Self.parseSnapshot(data: data, descriptor: descriptor)
    }

    internal static func parseSnapshot(data: Data, descriptor: ProviderDescriptor) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userStatus = root["userStatus"] as? [String: Any],
              let planStatus = userStatus["planStatus"] as? [String: Any] else {
            throw ProviderError.invalidResponse("Windsurf usage decode failed")
        }
        let plan = OfficialValueParser.string((planStatus["planInfo"] as? [String: Any])?["planName"]) ?? "unknown"
        guard let dailyRemaining = OfficialValueParser.double(planStatus["dailyQuotaRemainingPercent"]),
              let weeklyRemaining = OfficialValueParser.double(planStatus["weeklyQuotaRemainingPercent"]) else {
            throw ProviderError.invalidResponse("missing Windsurf quota values")
        }
        let dailyReset = OfficialValueParser.double(planStatus["dailyQuotaResetAtUnix"]).map { Date(timeIntervalSince1970: $0) }
        let weeklyReset = OfficialValueParser.double(planStatus["weeklyQuotaResetAtUnix"]).map { Date(timeIntervalSince1970: $0) }
        var windows = [
            UsageQuotaWindow(
                id: "\(descriptor.id)-daily",
                title: "Daily",
                remainingPercent: dailyRemaining,
                usedPercent: max(0, 100 - dailyRemaining),
                resetAt: dailyReset,
                kind: .session
            ),
            UsageQuotaWindow(
                id: "\(descriptor.id)-weekly",
                title: "Weekly",
                remainingPercent: weeklyRemaining,
                usedPercent: max(0, 100 - weeklyRemaining),
                resetAt: weeklyReset,
                kind: .weekly
            ),
        ]
        if let overageMicros = OfficialValueParser.double(planStatus["overageBalanceMicros"]), overageMicros > 0 {
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-overage",
                    title: "Extra",
                    remainingPercent: 100,
                    usedPercent: 0,
                    resetAt: nil,
                    kind: .extraUsage
                )
            )
        }
        let remaining = windows.map(\.remainingPercent).min() ?? 0
        var extras = ["planType": plan]
        if let overageMicros = OfficialValueParser.double(planStatus["overageBalanceMicros"]) {
            extras["overageBalance"] = String(format: "%.2f", overageMicros / 1_000_000)
        }
        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "Plan \(plan) | Daily \(Int(dailyRemaining.rounded()))% | Weekly \(Int(weeklyRemaining.rounded()))%",
            quotaWindows: windows,
            sourceLabel: "API",
            accountLabel: nil,
            extras: extras,
            rawMeta: [:]
        )
    }
}
