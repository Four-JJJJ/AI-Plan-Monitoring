import Foundation

final class RelayAdapterRegistry: @unchecked Sendable {
    static let shared = RelayAdapterRegistry()

    private let fileManager: FileManager
    private let bundledManifests: [RelayAdapterManifest]

    init(
        fileManager: FileManager = .default,
        builtInManifests: [RelayAdapterManifest]? = nil
    ) {
        self.fileManager = fileManager
        self.bundledManifests = builtInManifests ?? Self.loadBundledManifests()
    }

    func manifest(for baseURL: String, preferredID: String? = nil) -> RelayAdapterManifest {
        let all = availableManifests()
        if let preferredID,
           let matched = all.first(where: { $0.id == preferredID }) {
            return decorate(matched)
        }

        let host = URL(string: ProviderDescriptor.normalizeRelayBaseURL(baseURL))?.host?.lowercased()
        if let host,
           let matched = all
            .filter({ $0.match.hostPatterns.contains(where: { $0 != "*" }) })
            .sorted(by: Self.compareSpecificity)
            .first(where: { manifest in
                manifest.match.hostPatterns.contains(where: { Self.host(host, matches: $0) && $0 != "*" })
            }) {
            return decorate(matched)
        }

        return decorate(all.first(where: { $0.id == "generic-newapi" }) ?? Self.genericManifest)
    }

    func manifest(id: String) -> RelayAdapterManifest? {
        availableManifests().first(where: { $0.id == id }).map(decorate)
    }

    func builtInManifests() -> [RelayAdapterManifest] {
        bundledManifests
            .filter { !Self.isLegacyRelayExampleManifest($0) }
            .sorted { $0.id < $1.id }
            .map(decorate)
    }

    func availableManifests() -> [RelayAdapterManifest] {
        var merged: [String: RelayAdapterManifest] = [:]
        for manifest in bundledManifests {
            merged[manifest.id] = manifest
        }
        for manifest in loadLocalManifests() {
            merged[manifest.id] = manifest
        }
        return merged.values
            .filter { !Self.isLegacyRelayExampleManifest($0) }
            .sorted { $0.id < $1.id }
            .map(decorate)
    }

    private func decorate(_ manifest: RelayAdapterManifest) -> RelayAdapterManifest {
        var copy = manifest
        switch copy.id {
        case "ailinyu":
            copy.displayMode = .hybrid
            copy.supportsBrowserFallback = true
            copy.supportsSeparateBalanceAuth = true
        case "generic-newapi", "deepseek", "hongmacc", "xiaomimimo", "moonshot", "minimax":
            copy.displayMode = .balance
            copy.supportsBrowserFallback = true
            copy.supportsSeparateBalanceAuth = true
        default:
            break
        }

        if copy.setup?.diagnosticHints == nil {
            var setup = copy.setup ?? RelaySetupManifest()
            setup.diagnosticHints = diagnosticHints(for: copy.id)
            copy.setup = setup
        }
        return copy
    }

    private func diagnosticHints(for id: String) -> RelaySetupManifest.LocalizedText? {
        switch id {
        case "ailinyu":
            return .init(
                zhHans: "优先确认 API Key 与后台访问令牌分别填写正确；该站点可同时展示 token 配额和账户余额。",
                en: "Confirm the API key and dashboard access token separately. This site can expose both token quota and account balance."
            )
        case "deepseek", "hongmacc", "xiaomimimo", "moonshot", "minimax":
            return .init(
                zhHans: "测试连接时会优先使用当前模板的默认余额接口；若站点返回结构不同，再展开高级设置覆盖路径。",
                en: "Connection testing uses the template's default balance endpoint first. Open Advanced settings only if the site returns a different shape."
            )
        case "generic-newapi":
            return .init(
                zhHans: "先尝试标准 New API 配置；只有当站点接口路径或字段不兼容时再改高级设置。",
                en: "Start with the standard New API template. Change Advanced settings only when the site uses different paths or field names."
            )
        default:
            return nil
        }
    }

    private func loadLocalManifests() -> [RelayAdapterManifest] {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return []
        }
        let directory = appSupport
            .appendingPathComponent("AIPlanMonitor", isDirectory: true)
            .appendingPathComponent("relay-adapters", isDirectory: true)
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }

        let decoder = JSONDecoder()
        var manifests: [RelayAdapterManifest] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? decoder.decode(RelayAdapterManifest.self, from: data) else {
                continue
            }
            manifests.append(manifest)
        }
        return manifests
    }

    private static func loadBundledManifests() -> [RelayAdapterManifest] {
        let decoder = JSONDecoder()
        guard let resourceURL = Bundle.module.resourceURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil) else {
            return [genericManifest]
        }

        var manifests: [RelayAdapterManifest] = []
        for url in urls where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? decoder.decode(RelayAdapterManifest.self, from: data) else {
                continue
            }
            manifests.append(manifest)
        }
        manifests.sort { $0.id < $1.id }

        return manifests.isEmpty ? [genericManifest] : manifests
    }

    private static func host(_ host: String, matches pattern: String) -> Bool {
        let lowered = pattern.lowercased()
        if lowered == "*" {
            return true
        }
        if lowered.hasPrefix("*.") {
            return host == String(lowered.dropFirst(2)) || host.hasSuffix(String(lowered.dropFirst(1)))
        }
        return host == lowered || host.hasSuffix(".\(lowered)")
    }

    private static func compareSpecificity(lhs: RelayAdapterManifest, rhs: RelayAdapterManifest) -> Bool {
        lhs.match.hostPatterns.map(\.count).max() ?? 0 > rhs.match.hostPatterns.map(\.count).max() ?? 0
    }

    private static func isLegacyRelayExampleManifest(_ manifest: RelayAdapterManifest) -> Bool {
        let normalizedID = manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedDisplayName = manifest.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedDefaultDisplayName = manifest.match.defaultDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedHosts = manifest.match.hostPatterns.compactMap(Self.normalizeHostPattern)
        let hasRelayExampleHost = normalizedHosts.contains(where: Self.isRelayExampleHost)
        let hasExampleHost = normalizedHosts.contains(where: Self.isExampleHost)
        let hasRelayExampleID = normalizedID.contains("relay-example")
        let hasRelayExampleName = normalizedDisplayName.contains("relay example")
            || (normalizedDefaultDisplayName?.contains("relay example") ?? false)

        if hasRelayExampleHost {
            return true
        }

        if hasRelayExampleID || hasRelayExampleName {
            return true
        }

        return hasExampleHost && looksLikeGenericRelaySample(manifest)
    }

    private static func normalizeHostPattern(_ pattern: String) -> String? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        var hostPart = trimmed
        if let parsedHost = URL(string: trimmed)?.host?.lowercased() {
            hostPart = parsedHost
        } else {
            hostPart = hostPart
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
            if let slash = hostPart.firstIndex(of: "/") {
                hostPart = String(hostPart[..<slash])
            }
            if let query = hostPart.firstIndex(of: "?") {
                hostPart = String(hostPart[..<query])
            }
            if let hash = hostPart.firstIndex(of: "#") {
                hostPart = String(hostPart[..<hash])
            }
        }
        return hostPart.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isRelayExampleHost(_ hostPattern: String) -> Bool {
        let host = hostPattern.replacingOccurrences(of: "*.", with: "")
        return host == "relay.example.com" || host.hasSuffix(".relay.example.com")
    }

    private static func isExampleHost(_ hostPattern: String) -> Bool {
        let host = hostPattern.replacingOccurrences(of: "*.", with: "")
        return host == "example.com" || host.hasSuffix(".example.com")
    }

    private static func looksLikeGenericRelaySample(_ manifest: RelayAdapterManifest) -> Bool {
        let endpointPath = manifest.balanceRequest.path.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let remainingExpression = manifest.extract.remaining
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let usedExpression = manifest.extract.used?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        return endpointPath == "/api/user/self"
            && (remainingExpression.contains("quota") || usedExpression.contains("quota"))
    }

    static let genericManifest = RelayAdapterManifest(
        id: "generic-newapi",
        displayName: "Generic New API",
        match: RelayAdapterMatch(
            hostPatterns: ["*"],
            defaultDisplayName: "Generic New API",
            defaultTokenChannelEnabled: false,
            defaultBalanceChannelEnabled: true
        ),
        setup: RelaySetupManifest(
            requiredInputs: [.displayName, .baseURL, .balanceAuth, .userID],
            balanceAuthHint: .init(
                zhHans: "填写后台 Access Token，支持直接粘贴 `Bearer ...` 或纯 token。",
                en: "Enter the dashboard access token. Both `Bearer ...` and the raw token are accepted."
            ),
            userIDHint: .init(
                zhHans: "填写请求头 `New-Api-User` 对应的 userId。",
                en: "Enter the userId used for the `New-Api-User` request header."
            )
        ),
        authStrategies: [
            RelayAuthStrategy(kind: .savedBearer),
            RelayAuthStrategy(kind: .browserBearer),
            RelayAuthStrategy(kind: .savedCookieHeader),
            RelayAuthStrategy(kind: .browserCookieHeader)
        ],
        displayMode: .balance,
        supportsBrowserFallback: true,
        supportsSeparateBalanceAuth: true,
        balanceRequest: RelayRequestManifest(
            method: "GET",
            path: "/api/user/self",
            userIDHeader: "New-Api-User",
            authHeader: "Authorization",
            authScheme: "Bearer"
        ),
        tokenRequest: RelayTokenRequestManifest(),
        extract: RelayExtractManifest(
            success: "success",
            remaining: "div(data.quota,50000)",
            used: "div(data.used_quota,50000)",
            limit: "div(add(data.quota,data.used_quota),50000)",
            unit: "USD",
            accountLabel: "coalesce(data.group,\"默认套餐\")"
        ),
        postprocessID: nil
    )
}
