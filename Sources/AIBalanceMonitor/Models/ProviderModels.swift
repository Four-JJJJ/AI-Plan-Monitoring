import Foundation

enum ProviderType: String, Codable, CaseIterable {
    case codex
    case open
    case dragon
    case kimi
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case zhHans = "zh-Hans"
    case en = "en"

    var id: String { rawValue }
}

enum AuthKind: String, Codable {
    case none
    case bearer
    case localCodex
}

struct AuthConfig: Codable, Equatable {
    var kind: AuthKind
    var keychainService: String?
    var keychainAccount: String?

    static let none = AuthConfig(kind: .none)

    init(kind: AuthKind, keychainService: String? = nil, keychainAccount: String? = nil) {
        self.kind = kind
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
    }
}

struct AlertRule: Codable, Equatable {
    var lowRemaining: Double
    var maxConsecutiveFailures: Int
    var notifyOnAuthError: Bool
}

struct ProviderDescriptor: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var type: ProviderType
    var enabled: Bool
    var pollIntervalSec: Int
    var threshold: AlertRule
    var auth: AuthConfig
    var baseURL: String?
    var openConfig: OpenProviderConfig?
    var kimiConfig: KimiProviderConfig? = nil
}

enum KimiAuthMode: String, Codable, CaseIterable {
    case manual
    case auto
}

enum KimiBrowserKind: String, Codable, CaseIterable, Identifiable {
    case arc
    case chrome
    case safari
    case edge
    case brave
    case chromium

    var id: String { rawValue }
}

struct KimiProviderConfig: Codable, Equatable {
    var authMode: KimiAuthMode
    var manualTokenAccount: String
    var autoCookieEnabled: Bool
    var browserOrder: [KimiBrowserKind]
}

struct OpenProviderConfig: Codable, Equatable {
    var tokenUsageEnabled: Bool
    var accountBalance: RelayAccountBalanceConfig?
}

struct RelayAccountBalanceConfig: Codable, Equatable {
    var enabled: Bool
    var auth: AuthConfig
    var authHeader: String
    var authScheme: String
    var requestMethod: String?
    var requestBodyJSON: String?
    var endpointPath: String
    var userID: String?
    var userIDHeader: String
    var remainingJSONPath: String
    var usedJSONPath: String?
    var limitJSONPath: String?
    var successJSONPath: String?
    var unit: String
}

enum SnapshotStatus: String, Codable {
    case ok
    case warning
    case error
    case disabled
}

struct UsageSnapshot: Codable, Identifiable, Equatable {
    var id: String { source }
    var source: String
    var status: SnapshotStatus
    var remaining: Double?
    var used: Double?
    var limit: Double?
    var unit: String
    var updatedAt: Date
    var note: String
    var rawMeta: [String: String]
}

struct AppConfig: Codable, Equatable {
    var language: AppLanguage
    var providers: [ProviderDescriptor]

    init(language: AppLanguage = .zhHans, providers: [ProviderDescriptor]) {
        self.language = language
        self.providers = providers
    }

    static let `default` = AppConfig(
        language: .zhHans,
        providers: [
            ProviderDescriptor(
                id: "codex-official",
                name: "Official Codex",
                type: .codex,
                enabled: true,
                pollIntervalSec: 60,
                threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
                auth: AuthConfig(kind: .localCodex)
            ),
            ProviderDescriptor(
                id: "open-ailinyu",
                name: "open.ailinyu.de",
                type: .open,
                enabled: true,
                pollIntervalSec: 120,
                threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
                auth: AuthConfig(kind: .bearer, keychainService: "AIBalanceMonitor", keychainAccount: "open.ailinyu.de/sk-token"),
                baseURL: "https://open.ailinyu.de",
                openConfig: OpenProviderConfig(
                    tokenUsageEnabled: false,
                    accountBalance: RelayAccountBalanceConfig(
                        enabled: true,
                        auth: AuthConfig(
                            kind: .bearer,
                            keychainService: "AIBalanceMonitor",
                            keychainAccount: "open.ailinyu.de/session-cookie"
                        ),
                        authHeader: "Cookie",
                        authScheme: "",
                        requestMethod: "GET",
                        requestBodyJSON: nil,
                        endpointPath: "/api/user/self",
                        userID: "136",
                        userIDHeader: "New-Api-User",
                        remainingJSONPath: "data.quota",
                        usedJSONPath: "data.used_quota",
                        limitJSONPath: "data.request_quota",
                        successJSONPath: "success",
                        unit: "quota"
                    )
                )
            ),
            ProviderDescriptor(
                id: "dragoncode",
                name: "dragoncode.codes",
                type: .dragon,
                enabled: false,
                pollIntervalSec: 60,
                threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
                auth: AuthConfig(kind: .bearer, keychainService: "AIBalanceMonitor", keychainAccount: "dragoncode.codes/auth_token"),
                baseURL: "https://dragoncode.codes",
                openConfig: OpenProviderConfig(
                    tokenUsageEnabled: false,
                    accountBalance: RelayAccountBalanceConfig(
                        enabled: true,
                        auth: AuthConfig(
                            kind: .bearer,
                            keychainService: "AIBalanceMonitor",
                            keychainAccount: "dragoncode.codes/auth_token"
                        ),
                        authHeader: "Authorization",
                        authScheme: "Bearer",
                        requestMethod: "GET",
                        requestBodyJSON: nil,
                        endpointPath: "/api/v1/auth/me",
                        userID: nil,
                        userIDHeader: "New-Api-User",
                        remainingJSONPath: "data.balance",
                        usedJSONPath: "",
                        limitJSONPath: "",
                        successJSONPath: "",
                        unit: "balance"
                    )
                )
            ),
            ProviderDescriptor(
                id: "hongmacc",
                name: "hongmacc.com",
                type: .open,
                enabled: false,
                pollIntervalSec: 60,
                threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
                auth: AuthConfig(kind: .bearer, keychainService: "AIBalanceMonitor", keychainAccount: "hongmacc.com/auth_token"),
                baseURL: "https://hongmacc.com",
                openConfig: OpenProviderConfig(
                    tokenUsageEnabled: false,
                    accountBalance: RelayAccountBalanceConfig(
                        enabled: true,
                        auth: AuthConfig(
                            kind: .bearer,
                            keychainService: "AIBalanceMonitor",
                            keychainAccount: "hongmacc.com/auth_token"
                        ),
                        authHeader: "Authorization",
                        authScheme: "Bearer",
                        requestMethod: "GET",
                        requestBodyJSON: nil,
                        endpointPath: "/api/user/assets",
                        userID: nil,
                        userIDHeader: "New-Api-User",
                        remainingJSONPath: "sum(quotaCards.*.remainingQuota)",
                        usedJSONPath: "",
                        limitJSONPath: "",
                        successJSONPath: "",
                        unit: "CNY"
                    )
                )
            ),
            ProviderDescriptor(
                id: "kimi-coding",
                name: "Kimi (For Coding)",
                type: .kimi,
                enabled: true,
                pollIntervalSec: 60,
                threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
                auth: AuthConfig(kind: .bearer, keychainService: "AIBalanceMonitor", keychainAccount: "kimi.com/kimi-auth-manual"),
                baseURL: "https://www.kimi.com",
                kimiConfig: KimiProviderConfig(
                    authMode: .auto,
                    manualTokenAccount: "kimi.com/kimi-auth-manual",
                    autoCookieEnabled: true,
                    browserOrder: [.arc, .chrome, .safari, .edge, .brave, .chromium]
                )
            )
        ]
    )

    private enum CodingKeys: String, CodingKey {
        case language
        case providers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .zhHans
        let decodedProviders = try container.decodeIfPresent([ProviderDescriptor].self, forKey: .providers) ?? AppConfig.default.providers
        self.providers = decodedProviders.map { $0.normalized() }
    }
}

extension ProviderDescriptor {
    func normalized() -> ProviderDescriptor {
        var copy = self
        if type == .open || type == .dragon {
            if copy.openConfig == nil {
                copy.openConfig = Self.defaultOpenConfig(
                    id: id,
                    baseURL: baseURL,
                    type: type,
                    auth: auth
                )
            } else if copy.openConfig?.accountBalance == nil {
                var cfg = copy.openConfig!
                cfg.accountBalance = Self.defaultAccountBalanceConfig(
                    id: id,
                    baseURL: baseURL,
                    type: type,
                    auth: auth
                )
                copy.openConfig = cfg
            }
        } else if type == .kimi {
            if copy.kimiConfig == nil {
                copy.kimiConfig = Self.defaultKimiConfig(auth: auth)
            }
            if copy.baseURL?.isEmpty ?? true {
                copy.baseURL = "https://www.kimi.com"
            }
        }
        return copy
    }

    private static func defaultKimiConfig(auth: AuthConfig) -> KimiProviderConfig {
        KimiProviderConfig(
            authMode: .auto,
            manualTokenAccount: auth.keychainAccount ?? "kimi.com/kimi-auth-manual",
            autoCookieEnabled: true,
            browserOrder: [.arc, .chrome, .safari, .edge, .brave, .chromium]
        )
    }

    static func makeOpenRelay(name: String, baseURL: String, keychainService: String = "AIBalanceMonitor") -> ProviderDescriptor {
        let normalizedBaseURL = Self.normalizeBaseURL(baseURL)
        let host = URL(string: normalizedBaseURL)?.host ?? "relay"
        let hostSlug = host.replacingOccurrences(of: ".", with: "-")
        let id = "open-\(hostSlug)-\(Int(Date().timeIntervalSince1970))"
        return ProviderDescriptor(
            id: id,
            name: name.isEmpty ? host : name,
            type: .open,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .bearer, keychainService: keychainService, keychainAccount: "\(host)/sk-token"),
            baseURL: normalizedBaseURL,
            openConfig: OpenProviderConfig(
                tokenUsageEnabled: true,
                accountBalance: defaultAccountBalanceConfig(id: id, baseURL: normalizedBaseURL, keychainService: keychainService)
            )
        )
    }

    private static func defaultOpenConfig(
        id: String,
        baseURL: String?,
        type: ProviderType = .open,
        auth: AuthConfig = AuthConfig.none,
        keychainService: String = "AIBalanceMonitor"
    ) -> OpenProviderConfig {
        let preset = relayPreset(for: baseURL, type: type)
        return OpenProviderConfig(
            tokenUsageEnabled: preset?.tokenUsageEnabled ?? (type == .open),
            accountBalance: defaultAccountBalanceConfig(
                id: id,
                baseURL: baseURL,
                type: type,
                auth: auth.withFallback(
                    service: keychainService,
                    account: preset?.keychainAccount
                ),
                keychainService: keychainService
            )
        )
    }

    private static func defaultAccountBalanceConfig(
        id: String,
        baseURL: String?,
        type: ProviderType = .open,
        auth: AuthConfig = AuthConfig.none,
        keychainService: String = "AIBalanceMonitor"
    ) -> RelayAccountBalanceConfig {
        let normalized = normalizeBaseURL(baseURL ?? "")
        let host = URL(string: normalized)?.host ?? id
        let preset = relayPreset(for: baseURL, type: type)
        let accountKey = auth.keychainAccount ?? preset?.keychainAccount ?? "\(host)/system-access-token"
        return RelayAccountBalanceConfig(
            enabled: preset?.accountBalanceEnabled ?? false,
            auth: AuthConfig(
                kind: .bearer,
                keychainService: keychainService,
                keychainAccount: accountKey
            ),
            authHeader: preset?.authHeader ?? "Authorization",
            authScheme: preset?.authScheme ?? "Bearer",
            requestMethod: preset?.requestMethod,
            requestBodyJSON: preset?.requestBodyJSON,
            endpointPath: preset?.endpointPath ?? ((type == .dragon) ? "/api/v1/user/self" : "/api/user/self"),
            userID: preset?.defaultUserID,
            userIDHeader: preset?.userIDHeader ?? "New-Api-User",
            remainingJSONPath: preset?.remainingJSONPath ?? "data.quota",
            usedJSONPath: preset?.usedJSONPath,
            limitJSONPath: preset?.limitJSONPath,
            successJSONPath: preset?.successJSONPath,
            unit: preset?.unit ?? "quota"
        )
    }

    private static func relayPreset(for baseURL: String?, type: ProviderType) -> RelaySitePreset? {
        let normalized = normalizeBaseURL(baseURL ?? "")
        guard let host = URL(string: normalized)?.host?.lowercased() else {
            return nil
        }

        if host.contains("open.ailinyu.de") {
            return RelaySitePreset(
                tokenUsageEnabled: false,
                accountBalanceEnabled: true,
                keychainAccount: "open.ailinyu.de/session-cookie",
                authHeader: "Cookie",
                authScheme: "",
                requestMethod: "GET",
                requestBodyJSON: nil,
                endpointPath: "/api/user/self",
                defaultUserID: "136",
                userIDHeader: "New-Api-User",
                remainingJSONPath: "data.quota",
                usedJSONPath: "data.used_quota",
                limitJSONPath: "data.request_quota",
                successJSONPath: "success",
                unit: "quota"
            )
        }

        if host.contains("dragoncode.codes") || type == .dragon {
            return RelaySitePreset(
                tokenUsageEnabled: false,
                accountBalanceEnabled: true,
                keychainAccount: "dragoncode.codes/auth_token",
                authHeader: "Authorization",
                authScheme: "Bearer",
                requestMethod: "GET",
                requestBodyJSON: nil,
                endpointPath: "/api/v1/auth/me",
                defaultUserID: nil,
                userIDHeader: "New-Api-User",
                remainingJSONPath: "data.balance",
                usedJSONPath: nil,
                limitJSONPath: nil,
                successJSONPath: nil,
                unit: "balance"
            )
        }

        if host.contains("hongmacc.com") {
            return RelaySitePreset(
                tokenUsageEnabled: false,
                accountBalanceEnabled: true,
                keychainAccount: "hongmacc.com/auth_token",
                authHeader: "Authorization",
                authScheme: "Bearer",
                requestMethod: "GET",
                requestBodyJSON: nil,
                endpointPath: "/api/user/assets",
                defaultUserID: nil,
                userIDHeader: "New-Api-User",
                remainingJSONPath: "sum(quotaCards.*.remainingQuota)",
                usedJSONPath: nil,
                limitJSONPath: nil,
                successJSONPath: nil,
                unit: "CNY"
            )
        }

        return nil
    }

    private static func normalizeBaseURL(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            value = "https://open.ailinyu.de"
        }
        if !value.contains("://") {
            value = "https://" + value
        }
        if value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}

private struct RelaySitePreset {
    let tokenUsageEnabled: Bool
    let accountBalanceEnabled: Bool
    let keychainAccount: String
    let authHeader: String
    let authScheme: String
    let requestMethod: String?
    let requestBodyJSON: String?
    let endpointPath: String
    let defaultUserID: String?
    let userIDHeader: String
    let remainingJSONPath: String
    let usedJSONPath: String?
    let limitJSONPath: String?
    let successJSONPath: String?
    let unit: String
}

private extension AuthConfig {
    func withFallback(service: String, account: String?) -> AuthConfig {
        AuthConfig(
            kind: kind,
            keychainService: keychainService ?? service,
            keychainAccount: keychainAccount ?? account
        )
    }
}

extension AppConfig {
    func migratedWithSiteDefaults() -> AppConfig {
        var migrated = self

        for defaultProvider in AppConfig.default.providers {
            if let idx = migrated.providers.firstIndex(where: { $0.id == defaultProvider.id }) {
                migrated.providers[idx] = migrated.providers[idx].migratedSiteDefaults(from: defaultProvider)
            } else {
                migrated.providers.append(defaultProvider)
            }
        }

        return migrated
    }
}

private extension ProviderDescriptor {
    func migratedSiteDefaults(from defaults: ProviderDescriptor) -> ProviderDescriptor {
        var copy = self

        if (copy.baseURL ?? "").isEmpty {
            copy.baseURL = defaults.baseURL
        }

        if copy.type == .kimi {
            if copy.kimiConfig == nil {
                copy.kimiConfig = defaults.kimiConfig
            } else if copy.kimiConfig?.browserOrder.isEmpty ?? true {
                copy.kimiConfig?.browserOrder = defaults.kimiConfig?.browserOrder ?? [.arc, .chrome, .safari, .edge, .brave, .chromium]
            }
            return copy
        }

        guard (copy.type == .open || copy.type == .dragon),
              let defaultOpen = defaults.openConfig else {
            return copy
        }

        if copy.openConfig == nil {
            copy.openConfig = defaultOpen
            return copy
        }

        guard var account = copy.openConfig?.accountBalance,
              let defaultAccount = defaultOpen.accountBalance else {
            if copy.openConfig?.accountBalance == nil {
                copy.openConfig?.accountBalance = defaultOpen.accountBalance
            }
            return copy
        }

        if copy.id == "open-ailinyu" {
            if copy.pollIntervalSec < 120 {
                copy.pollIntervalSec = 120
            }
            let hasLegacyAuthHeader = account.authHeader.caseInsensitiveCompare("Authorization") == .orderedSame
            let hasLegacyAccountKey = (account.auth.keychainAccount ?? "").contains("/sk-token")

            if hasLegacyAuthHeader || hasLegacyAccountKey {
                let preserveEnabled = account.enabled
                let preserveUserID = account.userID
                let preserveService = account.auth.keychainService

                account = defaultAccount
                account.enabled = preserveEnabled
                if let preserveUserID, !preserveUserID.isEmpty {
                    account.userID = preserveUserID
                }
                if let preserveService, !preserveService.isEmpty {
                    account.auth.keychainService = preserveService
                }
            }
        }

        if copy.id == "dragoncode" || copy.id == "hongmacc" {
            let tokenEnabled = copy.openConfig?.tokenUsageEnabled ?? false
            if !tokenEnabled {
                account.enabled = true
            }
        }

        copy.openConfig?.accountBalance = account
        return copy
    }
}
