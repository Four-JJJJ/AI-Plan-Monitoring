import Foundation

final class RelayAdapterRegistry: @unchecked Sendable {
    static let shared = RelayAdapterRegistry()

    private let fileManager: FileManager
    private let builtInManifests: [RelayAdapterManifest]

    init(
        fileManager: FileManager = .default,
        builtInManifests: [RelayAdapterManifest]? = nil
    ) {
        self.fileManager = fileManager
        self.builtInManifests = builtInManifests ?? Self.loadBundledManifests()
    }

    func manifest(for baseURL: String, preferredID: String? = nil) -> RelayAdapterManifest {
        let all = availableManifests()
        if let preferredID,
           let matched = all.first(where: { $0.id == preferredID }) {
            return matched
        }

        let host = URL(string: ProviderDescriptor.normalizeRelayBaseURL(baseURL))?.host?.lowercased()
        if let host,
           let matched = all
            .filter({ $0.match.hostPatterns.contains(where: { $0 != "*" }) })
            .sorted(by: Self.compareSpecificity)
            .first(where: { manifest in
                manifest.match.hostPatterns.contains(where: { Self.host(host, matches: $0) && $0 != "*" })
            }) {
            return matched
        }

        return all.first(where: { $0.id == "generic-newapi" }) ?? Self.genericManifest
    }

    func manifest(id: String) -> RelayAdapterManifest? {
        availableManifests().first(where: { $0.id == id })
    }

    func availableManifests() -> [RelayAdapterManifest] {
        var merged: [String: RelayAdapterManifest] = [:]
        for manifest in builtInManifests {
            merged[manifest.id] = manifest
        }
        for manifest in loadLocalManifests() {
            merged[manifest.id] = manifest
        }
        return merged.values.sorted { $0.id < $1.id }
    }

    private func loadLocalManifests() -> [RelayAdapterManifest] {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return []
        }
        let directory = appSupport
            .appendingPathComponent("AIBalanceMonitor", isDirectory: true)
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

    static let genericManifest = RelayAdapterManifest(
        id: "generic-newapi",
        displayName: "Generic New API",
        match: RelayAdapterMatch(
            hostPatterns: ["*"],
            defaultDisplayName: "Generic New API",
            defaultTokenChannelEnabled: true,
            defaultBalanceChannelEnabled: false
        ),
        setup: RelaySetupManifest(
            requiredInputs: [.displayName, .baseURL, .quotaAuth],
            quotaAuthHint: .init(
                zhHans: "填写站点提供的 API Key 或 sk- Token，支持直接粘贴 `sk-...` 或 `Bearer sk-...`。",
                en: "Enter the site's API key or sk token. Both `sk-...` and `Bearer sk-...` are accepted."
            ),
            balanceAuthHint: .init(
                zhHans: "如果站点余额接口需要单独认证，可以把后台 access token 或完整 Cookie 填在这里。",
                en: "If the balance endpoint uses separate auth, paste the dashboard access token or full Cookie here."
            )
        ),
        authStrategies: [
            RelayAuthStrategy(kind: .savedBearer),
            RelayAuthStrategy(kind: .browserBearer),
            RelayAuthStrategy(kind: .savedCookieHeader),
            RelayAuthStrategy(kind: .browserCookieHeader)
        ],
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
            remaining: "data.quota",
            used: "data.used_quota",
            limit: "data.request_quota",
            unit: "quota"
        ),
        postprocessID: nil
    )
}
