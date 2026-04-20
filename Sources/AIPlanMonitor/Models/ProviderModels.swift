import Foundation

enum ProviderFamily: String, Codable, CaseIterable {
    case official
    case thirdParty
}

enum ProviderType: String, Codable, CaseIterable {
    case codex
    case claude
    case gemini
    case copilot
    case zai
    case amp
    case cursor
    case jetbrains
    case kiro
    case windsurf
    case trae
    case relay
    case open
    case dragon
    case kimi
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case zhHans = "zh-Hans"
    case en = "en"

    var id: String { rawValue }
}

enum StatusBarDisplayStyle: String, Codable, CaseIterable, Identifiable {
    case iconPercent
    case barNamePercent

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

enum OfficialSourceMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case api
    case cli
    case web

    var id: String { rawValue }
}

enum OfficialWebMode: String, Codable, CaseIterable, Identifiable {
    case disabled
    case autoImport
    case manual

    var id: String { rawValue }
}

enum OfficialQuotaDisplayMode: String, Codable, CaseIterable, Identifiable {
    case remaining
    case used

    var id: String { rawValue }
}

struct OfficialProviderConfig: Codable, Equatable {
    var sourceMode: OfficialSourceMode
    var webMode: OfficialWebMode
    var manualCookieAccount: String?
    var autoDiscoveryEnabled: Bool
    var quotaDisplayMode: OfficialQuotaDisplayMode
    var showPlanTypeInMenuBar: Bool

    init(
        sourceMode: OfficialSourceMode = .auto,
        webMode: OfficialWebMode = .disabled,
        manualCookieAccount: String? = nil,
        autoDiscoveryEnabled: Bool = true,
        quotaDisplayMode: OfficialQuotaDisplayMode = .remaining,
        showPlanTypeInMenuBar: Bool = true
    ) {
        self.sourceMode = sourceMode
        self.webMode = webMode
        self.manualCookieAccount = manualCookieAccount
        self.autoDiscoveryEnabled = autoDiscoveryEnabled
        self.quotaDisplayMode = quotaDisplayMode
        self.showPlanTypeInMenuBar = showPlanTypeInMenuBar
    }

    private enum CodingKeys: String, CodingKey {
        case sourceMode
        case webMode
        case manualCookieAccount
        case autoDiscoveryEnabled
        case quotaDisplayMode
        case showPlanTypeInMenuBar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceMode = try container.decodeIfPresent(OfficialSourceMode.self, forKey: .sourceMode) ?? .auto
        self.webMode = try container.decodeIfPresent(OfficialWebMode.self, forKey: .webMode) ?? .disabled
        self.manualCookieAccount = try container.decodeIfPresent(String.self, forKey: .manualCookieAccount)
        self.autoDiscoveryEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoDiscoveryEnabled) ?? true
        self.quotaDisplayMode = try container.decodeIfPresent(OfficialQuotaDisplayMode.self, forKey: .quotaDisplayMode) ?? .remaining
        self.showPlanTypeInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showPlanTypeInMenuBar) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceMode, forKey: .sourceMode)
        try container.encode(webMode, forKey: .webMode)
        try container.encodeIfPresent(manualCookieAccount, forKey: .manualCookieAccount)
        try container.encode(autoDiscoveryEnabled, forKey: .autoDiscoveryEnabled)
        try container.encode(quotaDisplayMode, forKey: .quotaDisplayMode)
        try container.encode(showPlanTypeInMenuBar, forKey: .showPlanTypeInMenuBar)
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
    var family: ProviderFamily
    var type: ProviderType
    var enabled: Bool
    var pollIntervalSec: Int
    var threshold: AlertRule
    var auth: AuthConfig
    var baseURL: String?
    var officialConfig: OfficialProviderConfig?
    var relayConfig: RelayProviderConfig?
    var openConfig: OpenProviderConfig?
    var kimiConfig: KimiProviderConfig?

    init(
        id: String,
        name: String,
        family: ProviderFamily = .thirdParty,
        type: ProviderType,
        enabled: Bool,
        pollIntervalSec: Int,
        threshold: AlertRule,
        auth: AuthConfig,
        baseURL: String? = nil,
        officialConfig: OfficialProviderConfig? = nil,
        relayConfig: RelayProviderConfig? = nil,
        openConfig: OpenProviderConfig? = nil,
        kimiConfig: KimiProviderConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.type = type
        self.enabled = enabled
        self.pollIntervalSec = pollIntervalSec
        self.threshold = threshold
        self.auth = auth
        self.baseURL = baseURL
        self.officialConfig = officialConfig
        self.relayConfig = relayConfig
        self.openConfig = openConfig
        self.kimiConfig = kimiConfig
    }
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
    case firefox
    case opera
    case operaGX
    case vivaldi

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

enum RelayDisplayMode: String, Codable, Equatable {
    case balance
    case quotaPercent
    case hybrid
}

enum FetchHealth: String, Codable, Equatable {
    case ok
    case authExpired
    case rateLimited
    case endpointMisconfigured
    case unreachable
}

enum ValueFreshness: String, Codable, Equatable {
    case live
    case cachedFallback
    case empty
}

enum UsageQuotaKind: String, Codable, Equatable {
    case session
    case weekly
    case reviews
    case credits
    case extraUsage
    case modelWeekly
    case custom
}

struct UsageQuotaWindow: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var remainingPercent: Double
    var usedPercent: Double
    var resetAt: Date?
    var kind: UsageQuotaKind

    init(
        id: String,
        title: String,
        remainingPercent: Double,
        usedPercent: Double,
        resetAt: Date? = nil,
        kind: UsageQuotaKind
    ) {
        self.id = id
        self.title = title
        self.remainingPercent = remainingPercent
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.kind = kind
    }
}

struct UsageSnapshot: Codable, Identifiable, Equatable {
    var id: String { source }
    var source: String
    var status: SnapshotStatus
    var fetchHealth: FetchHealth
    var valueFreshness: ValueFreshness
    var remaining: Double?
    var used: Double?
    var limit: Double?
    var unit: String
    var updatedAt: Date
    var note: String
    var quotaWindows: [UsageQuotaWindow]
    var sourceLabel: String
    var accountLabel: String?
    var authSourceLabel: String?
    var diagnosticCode: String?
    var extras: [String: String]
    var rawMeta: [String: String]

    init(
        source: String,
        status: SnapshotStatus,
        fetchHealth: FetchHealth = .ok,
        valueFreshness: ValueFreshness = .live,
        remaining: Double?,
        used: Double?,
        limit: Double?,
        unit: String,
        updatedAt: Date,
        note: String,
        quotaWindows: [UsageQuotaWindow] = [],
        sourceLabel: String = "",
        accountLabel: String? = nil,
        authSourceLabel: String? = nil,
        diagnosticCode: String? = nil,
        extras: [String: String] = [:],
        rawMeta: [String: String] = [:]
    ) {
        self.source = source
        self.status = status
        self.fetchHealth = fetchHealth
        self.valueFreshness = valueFreshness
        self.remaining = remaining
        self.used = used
        self.limit = limit
        self.unit = unit
        self.updatedAt = updatedAt
        self.note = note
        self.quotaWindows = quotaWindows
        self.sourceLabel = sourceLabel
        self.accountLabel = accountLabel
        self.authSourceLabel = authSourceLabel
        self.diagnosticCode = diagnosticCode
        self.extras = extras
        self.rawMeta = rawMeta
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case status
        case fetchHealth
        case valueFreshness
        case remaining
        case used
        case limit
        case unit
        case updatedAt
        case note
        case quotaWindows
        case sourceLabel
        case accountLabel
        case authSourceLabel
        case diagnosticCode
        case extras
        case rawMeta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(String.self, forKey: .source)
        status = try container.decode(SnapshotStatus.self, forKey: .status)
        fetchHealth = try container.decodeIfPresent(FetchHealth.self, forKey: .fetchHealth) ?? .ok
        valueFreshness = try container.decodeIfPresent(ValueFreshness.self, forKey: .valueFreshness) ?? .live
        remaining = try container.decodeIfPresent(Double.self, forKey: .remaining)
        used = try container.decodeIfPresent(Double.self, forKey: .used)
        limit = try container.decodeIfPresent(Double.self, forKey: .limit)
        unit = try container.decode(String.self, forKey: .unit)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        note = try container.decode(String.self, forKey: .note)
        quotaWindows = try container.decodeIfPresent([UsageQuotaWindow].self, forKey: .quotaWindows) ?? []
        sourceLabel = try container.decodeIfPresent(String.self, forKey: .sourceLabel) ?? ""
        accountLabel = try container.decodeIfPresent(String.self, forKey: .accountLabel)
        authSourceLabel = try container.decodeIfPresent(String.self, forKey: .authSourceLabel)
        diagnosticCode = try container.decodeIfPresent(String.self, forKey: .diagnosticCode)
        extras = try container.decodeIfPresent([String: String].self, forKey: .extras) ?? [:]
        rawMeta = try container.decodeIfPresent([String: String].self, forKey: .rawMeta) ?? [:]
    }
}

struct RelayDiagnosticSnapshotPreview: Equatable {
    var remaining: Double?
    var used: Double?
    var limit: Double?
    var unit: String
}

struct RelayDiagnosticResult: Equatable {
    var success: Bool
    var fetchHealth: FetchHealth
    var resolvedAdapterID: String
    var resolvedAuthSource: String?
    var message: String
    var snapshotPreview: RelayDiagnosticSnapshotPreview?
}

struct CodexSlotViewModel: Identifiable, Equatable {
    var id: String { slotID.rawValue }
    var slotID: CodexSlotID
    var title: String
    var snapshot: UsageSnapshot
    var isActive: Bool
    var lastSeenAt: Date
    var displayName: String
    var isSwitching: Bool = false
    var canSwitch: Bool = false
    var isCurrentSystemAccount: Bool = false
    var profileDisplayName: String?
    var switchMessage: String?
    var switchMessageIsError: Bool = false
}

struct CodexAccountProfile: Codable, Equatable, Identifiable {
    var id: String { slotID.rawValue }
    var slotID: CodexSlotID
    var displayName: String
    var authJSON: String
    var accountId: String?
    var accountEmail: String?
    var accountSubject: String? = nil
    var tenantKey: String? = nil
    var identityKey: String? = nil
    var credentialFingerprint: String?
    var lastImportedAt: Date
    var isCurrentSystemAccount: Bool
}

struct CodexSwitchFeedback: Equatable {
    var message: String
    var isError: Bool
}

enum ClaudeProfileSource: String, Codable, CaseIterable, Identifiable {
    case configDir
    case manualCredentials

    var id: String { rawValue }
}

struct ClaudeSlotViewModel: Identifiable, Equatable {
    var id: String { slotID.rawValue }
    var slotID: CodexSlotID
    var title: String
    var snapshot: UsageSnapshot
    var isActive: Bool
    var lastSeenAt: Date
    var displayName: String
    var source: ClaudeProfileSource?
    var isSwitching: Bool = false
    var canSwitch: Bool = false
    var isCurrentSystemAccount: Bool = false
    var profileDisplayName: String?
    var switchMessage: String?
    var switchMessageIsError: Bool = false
}

struct ClaudeAccountProfile: Codable, Equatable, Identifiable {
    var id: String { slotID.rawValue }
    var slotID: CodexSlotID
    var displayName: String
    var source: ClaudeProfileSource
    var configDir: String?
    var credentialsJSON: String?
    var accountId: String?
    var accountEmail: String?
    var credentialFingerprint: String?
    var lastImportedAt: Date
    var isCurrentSystemAccount: Bool
}

struct ClaudeSwitchFeedback: Equatable {
    var message: String
    var isError: Bool
}

struct AppConfig: Codable, Equatable {
    var language: AppLanguage
    var launchAtLoginEnabled: Bool
    var simplifiedRelayConfig: Bool
    var showOfficialAccountEmailInMenuBar: Bool
    var statusBarProviderID: String?
    var statusBarMultiUsageEnabled: Bool
    var statusBarMultiProviderIDs: [String]
    var statusBarDisplayStyle: StatusBarDisplayStyle
    var providers: [ProviderDescriptor]

    init(
        language: AppLanguage = .zhHans,
        launchAtLoginEnabled: Bool = false,
        simplifiedRelayConfig: Bool = true,
        showOfficialAccountEmailInMenuBar: Bool = false,
        statusBarProviderID: String? = nil,
        statusBarMultiUsageEnabled: Bool = false,
        statusBarMultiProviderIDs: [String]? = nil,
        statusBarDisplayStyle: StatusBarDisplayStyle = .iconPercent,
        providers: [ProviderDescriptor]
    ) {
        let normalizedProviders = providers.map { $0.normalized() }
        let resolvedStatusProviderID = statusBarProviderID ?? Self.defaultStatusBarProviderID(from: normalizedProviders)
        self.language = language
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.simplifiedRelayConfig = simplifiedRelayConfig
        self.showOfficialAccountEmailInMenuBar = showOfficialAccountEmailInMenuBar
        self.statusBarProviderID = resolvedStatusProviderID
        self.statusBarMultiUsageEnabled = statusBarMultiUsageEnabled
        let decodedMultiProviderIDs = statusBarMultiProviderIDs
            ?? (resolvedStatusProviderID.map { [$0] } ?? [])
        self.statusBarMultiProviderIDs = Self.normalizedStatusBarMultiProviderIDs(
            decodedMultiProviderIDs,
            providers: normalizedProviders
        )
        self.statusBarDisplayStyle = statusBarDisplayStyle
        self.providers = normalizedProviders
    }

    static let `default` = AppConfig(
        language: .zhHans,
        providers: [
            .defaultOfficialCodex(),
            .defaultOfficialClaude(),
            .defaultOfficialGemini(),
            .defaultOfficialCopilot(),
            .defaultOfficialZai(),
            .defaultOfficialAmp(),
            .defaultOfficialCursor(),
            .defaultOfficialJetBrains(),
            .defaultOfficialKiro(),
            .defaultOfficialWindsurf(),
            .defaultOfficialKimi(),
            .defaultOfficialTrae()
        ]
    )

    private enum CodingKeys: String, CodingKey {
        case language
        case launchAtLoginEnabled
        case simplifiedRelayConfig
        case showOfficialAccountEmailInMenuBar
        case statusBarProviderID
        case statusBarMultiUsageEnabled
        case statusBarMultiProviderIDs
        case statusBarDisplayStyle
        case providers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .zhHans
        self.launchAtLoginEnabled = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled) ?? false
        self.simplifiedRelayConfig = try container.decodeIfPresent(Bool.self, forKey: .simplifiedRelayConfig) ?? true
        self.showOfficialAccountEmailInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showOfficialAccountEmailInMenuBar) ?? false
        let decodedProviders = try container.decodeIfPresent([ProviderDescriptor].self, forKey: .providers) ?? AppConfig.default.providers
        self.providers = decodedProviders.map { $0.normalized() }
        let resolvedStatusProviderID = try container.decodeIfPresent(String.self, forKey: .statusBarProviderID)
            ?? Self.defaultStatusBarProviderID(from: providers)
        self.statusBarProviderID = resolvedStatusProviderID
        self.statusBarMultiUsageEnabled = try container.decodeIfPresent(Bool.self, forKey: .statusBarMultiUsageEnabled) ?? false
        let decodedMultiProviderIDs = try container.decodeIfPresent([String].self, forKey: .statusBarMultiProviderIDs)
            ?? (resolvedStatusProviderID.map { [$0] } ?? [])
        self.statusBarMultiProviderIDs = Self.normalizedStatusBarMultiProviderIDs(
            decodedMultiProviderIDs,
            providers: providers
        )
        self.statusBarDisplayStyle = try container.decodeIfPresent(StatusBarDisplayStyle.self, forKey: .statusBarDisplayStyle)
            ?? .iconPercent
    }

    static func defaultStatusBarProviderID(from providers: [ProviderDescriptor]) -> String? {
        if let codex = providers.first(where: { $0.enabled && $0.type == .codex && $0.family == .official }) {
            return codex.id
        }
        return providers.first(where: \.enabled)?.id
    }

    static func normalizedStatusBarMultiProviderIDs(_ ids: [String], providers: [ProviderDescriptor]) -> [String] {
        let validProviderIDs = Set(providers.map(\.id))
        var seenIDs = Set<String>()
        var normalizedIDs: [String] = []
        for id in ids {
            guard validProviderIDs.contains(id), seenIDs.insert(id).inserted else { continue }
            normalizedIDs.append(id)
        }
        return normalizedIDs
    }
}

extension ProviderDescriptor {
    var isRelay: Bool {
        switch type {
        case .relay, .open, .dragon:
            return true
        case .codex, .claude, .gemini, .copilot, .zai, .amp, .cursor, .jetbrains, .kiro, .windsurf, .kimi, .trae:
            return false
        }
    }

    func normalized() -> ProviderDescriptor {
        var copy = self
        copy.auth = copy.auth.normalizedCredentialServiceName()
        if copy.type == .open || copy.type == .dragon {
            copy.type = .relay
        }

        switch copy.type {
        case .codex, .claude, .gemini, .copilot, .zai, .amp, .cursor, .jetbrains, .kiro, .windsurf, .trae:
            copy.family = .official
            if copy.officialConfig == nil {
                copy.officialConfig = Self.defaultOfficialConfig(type: copy.type)
            } else if copy.officialConfig?.manualCookieAccount?.isEmpty ?? true {
                copy.officialConfig?.manualCookieAccount = Self.defaultOfficialConfig(type: copy.type).manualCookieAccount
            }
            if copy.baseURL?.isEmpty ?? true {
                copy.baseURL = Self.defaultOfficialBaseURL(type: copy.type)
            }
            if copy.pollIntervalSec <= 0 {
                copy.pollIntervalSec = 60
            }
            return copy
        case .relay, .open, .dragon:
            copy.family = .thirdParty
            let normalizedBaseURL = Self.normalizeRelayBaseURL(copy.relayConfig?.baseURL ?? copy.baseURL ?? "")
            copy.baseURL = normalizedBaseURL
            if copy.relayConfig == nil {
                copy.relayConfig = Self.defaultRelayConfig(
                    id: id,
                    baseURL: normalizedBaseURL,
                    auth: auth,
                    legacyOpenConfig: copy.openConfig
                )
            } else {
                var relay = copy.relayConfig!
                relay.balanceAuth = relay.balanceAuth.normalizedCredentialServiceName()
                let originalAdapterID = relay.adapterID?.trimmingCharacters(in: .whitespacesAndNewlines)
                let allowAutoMatch = originalAdapterID == nil || originalAdapterID == "generic-newapi"
                let manifest = RelayAdapterRegistry.shared.manifest(
                    for: normalizedBaseURL,
                    preferredID: allowAutoMatch ? nil : originalAdapterID
                )
                relay.baseURL = normalizedBaseURL
                if allowAutoMatch {
                    relay.adapterID = manifest.id
                    if manifest.id != "generic-newapi",
                       Self.looksLikeGenericDefaultOverride(relay.manualOverrides) {
                        relay.manualOverrides = nil
                    }
                } else {
                    relay.adapterID = originalAdapterID ?? manifest.id
                }
                if relay.adapterID == "generic-newapi" {
                    relay.manualOverrides = Self.migrateGenericNewAPIDefaultOverride(relay.manualOverrides)
                }
                relay.balanceAuth = relay.balanceAuth.withFallback(
                    service: copy.auth.keychainService ?? KeychainService.defaultServiceName,
                    account: Self.defaultRelayBalanceAccount(
                        id: id,
                        baseURL: normalizedBaseURL,
                        adapterID: relay.adapterID ?? manifest.id
                    )
                )
                relay.balanceCredentialMode = relay.balanceCredentialMode ?? .manualPreferred
                copy.relayConfig = relay
            }
            copy.openConfig = nil
            if copy.pollIntervalSec <= 0 {
                copy.pollIntervalSec = id == "open-ailinyu" ? 120 : 60
            }
            if copy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let manifest = RelayAdapterRegistry.shared.manifest(
                    for: normalizedBaseURL,
                    preferredID: copy.relayConfig?.adapterID
                )
                copy.name = manifest.match.defaultDisplayName
                    ?? URL(string: normalizedBaseURL)?.host
                    ?? "Relay"
            }
            return copy
        case .kimi:
            if copy.family == .official || copy.id == "kimi-official" {
                copy.family = .official
                copy.name = "Kimi Coding"
                if copy.officialConfig == nil {
                    copy.officialConfig = Self.defaultOfficialConfig(type: .kimi)
                } else if copy.officialConfig?.manualCookieAccount?.isEmpty ?? true {
                    copy.officialConfig?.manualCookieAccount = Self.defaultOfficialConfig(type: .kimi).manualCookieAccount
                }
                if copy.baseURL?.isEmpty ?? true {
                    copy.baseURL = Self.defaultOfficialBaseURL(type: .kimi)
                }
                if copy.pollIntervalSec <= 0 {
                    copy.pollIntervalSec = 60
                }
                copy.kimiConfig = nil
                return copy
            }

            copy.family = .thirdParty
            if copy.kimiConfig == nil {
                copy.kimiConfig = Self.defaultKimiConfig(auth: auth)
            }
            if copy.baseURL?.isEmpty ?? true {
                copy.baseURL = "https://www.kimi.com"
            }
            return copy
        }
    }

    private static func defaultOfficialBaseURL(type: ProviderType) -> String {
        switch type {
        case .codex:
            return "https://chatgpt.com"
        case .claude:
            return "https://claude.ai"
        case .gemini:
            return "https://cloudcode-pa.googleapis.com"
        case .copilot:
            return "https://api.github.com"
        case .zai:
            return "https://api.z.ai"
        case .amp:
            return "https://ampcode.com"
        case .cursor:
            return "https://api2.cursor.sh"
        case .jetbrains:
            return "file://jetbrains-local"
        case .kiro:
            return "cli://kiro-cli"
        case .windsurf:
            return "https://server.codeium.com"
        case .kimi:
            return "https://api.kimi.com"
        case .trae:
            return "https://api-sg-central.trae.ai"
        case .relay, .open, .dragon:
            return ""
        }
    }

    static func defaultOfficialConfig(type: ProviderType) -> OfficialProviderConfig {
        switch type {
        case .codex:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .autoImport,
                manualCookieAccount: "official/codex/cookie-header",
                autoDiscoveryEnabled: true
            )
        case .claude:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .autoImport,
                manualCookieAccount: "official/claude/cookie-header",
                autoDiscoveryEnabled: true,
                quotaDisplayMode: .used
            )
        case .gemini:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .disabled,
                manualCookieAccount: nil,
                autoDiscoveryEnabled: true
            )
        case .copilot:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .disabled,
                manualCookieAccount: nil,
                autoDiscoveryEnabled: true
            )
        case .zai:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .disabled,
                manualCookieAccount: nil,
                autoDiscoveryEnabled: true
            )
        case .amp:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .disabled,
                manualCookieAccount: nil,
                autoDiscoveryEnabled: true
            )
        case .cursor:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .disabled,
                manualCookieAccount: nil,
                autoDiscoveryEnabled: true
            )
        case .jetbrains:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .disabled,
                manualCookieAccount: nil,
                autoDiscoveryEnabled: true
            )
        case .kiro:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .disabled,
                manualCookieAccount: nil,
                autoDiscoveryEnabled: true
            )
        case .windsurf:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .disabled,
                manualCookieAccount: nil,
                autoDiscoveryEnabled: true
            )
        case .kimi:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .disabled,
                manualCookieAccount: nil,
                autoDiscoveryEnabled: true
            )
        case .trae:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .disabled,
                manualCookieAccount: nil,
                autoDiscoveryEnabled: true
            )
        case .relay, .open, .dragon:
            return OfficialProviderConfig()
        }
    }

    private static func defaultKimiConfig(auth: AuthConfig) -> KimiProviderConfig {
        KimiProviderConfig(
            authMode: .auto,
            manualTokenAccount: auth.keychainAccount ?? "kimi.com/kimi-auth-manual",
            autoCookieEnabled: true,
            browserOrder: [.arc, .chrome, .safari, .edge, .brave, .firefox, .opera, .operaGX, .vivaldi, .chromium]
        )
    }

    static func makeOpenRelay(
        name: String,
        baseURL: String,
        preferredAdapterID: String? = nil,
        keychainService: String = KeychainService.defaultServiceName
    ) -> ProviderDescriptor {
        let normalizedBaseURL = Self.normalizeRelayBaseURL(baseURL)
        let host = URL(string: normalizedBaseURL)?.host ?? "relay"
        let hostSlug = host.replacingOccurrences(of: ".", with: "-")
        let id = "open-\(hostSlug)-\(Int(Date().timeIntervalSince1970))"
        return ProviderDescriptor(
            id: id,
            name: name.isEmpty ? host : name,
            family: .thirdParty,
            type: .relay,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .bearer, keychainService: keychainService, keychainAccount: "\(host)/sk-token"),
            baseURL: normalizedBaseURL,
            relayConfig: defaultRelayConfig(
                id: id,
                baseURL: normalizedBaseURL,
                preferredAdapterID: preferredAdapterID,
                auth: AuthConfig(kind: .bearer, keychainService: keychainService, keychainAccount: "\(host)/sk-token")
            )
        )
    }

    private static func defaultRelayConfig(
        id: String,
        baseURL: String?,
        preferredAdapterID: String? = nil,
        auth: AuthConfig = AuthConfig.none,
        legacyOpenConfig: OpenProviderConfig? = nil,
        keychainService: String = KeychainService.defaultServiceName
    ) -> RelayProviderConfig {
        let normalizedBaseURL = normalizeRelayBaseURL(baseURL ?? "")
        let adapterID = defaultRelayAdapterID(
            id: id,
            baseURL: normalizedBaseURL,
            legacyOpenConfig: legacyOpenConfig,
            preferredAdapterID: preferredAdapterID
        )
        let manifest = RelayAdapterRegistry.shared.manifest(
            for: normalizedBaseURL,
            preferredID: adapterID
        )
        let legacyAccount = legacyOpenConfig?.accountBalance?.auth
        return RelayProviderConfig(
            adapterID: manifest.id,
            baseURL: normalizedBaseURL,
            tokenChannelEnabled: legacyOpenConfig?.tokenUsageEnabled ?? manifest.match.defaultTokenChannelEnabled,
            balanceChannelEnabled: legacyOpenConfig?.accountBalance?.enabled ?? manifest.match.defaultBalanceChannelEnabled,
            balanceAuth: (legacyAccount ?? AuthConfig(kind: .bearer)).withFallback(
                service: auth.keychainService ?? keychainService,
                account: defaultRelayBalanceAccount(
                    id: id,
                    baseURL: normalizedBaseURL,
                    adapterID: manifest.id
                )
            ),
            balanceCredentialMode: .manualPreferred,
            manualOverrides: manualOverrides(from: legacyOpenConfig)
        )
    }

    private static func manualOverrides(from legacyOpenConfig: OpenProviderConfig?) -> RelayManualOverride? {
        guard let legacy = legacyOpenConfig?.accountBalance else { return nil }
        let overrides = RelayManualOverride(
            authHeader: legacy.authHeader,
            authScheme: legacy.authScheme,
            userID: legacy.userID,
            userIDHeader: legacy.userIDHeader,
            requestMethod: legacy.requestMethod,
            requestBodyJSON: legacy.requestBodyJSON,
            endpointPath: legacy.endpointPath,
            remainingExpression: legacy.remainingJSONPath,
            usedExpression: legacy.usedJSONPath,
            limitExpression: legacy.limitJSONPath,
            successExpression: legacy.successJSONPath,
            unitExpression: legacy.unit,
            accountLabelExpression: nil,
            staticHeaders: nil
        )
        return overrides.isEmpty ? nil : overrides
    }

    private static func defaultRelayBalanceAccount(
        id: String,
        baseURL: String?,
        adapterID: String
    ) -> String {
        let normalized = normalizeRelayBaseURL(baseURL ?? "")
        let host = URL(string: normalized)?.host ?? id
        switch adapterID {
        case "ailinyu":
            return "open.ailinyu.de/session-cookie"
        case "dragoncode":
            return "dragoncode.codes/auth_token"
        case "hongmacc":
            return "hongmacc.com/auth_token"
        case "xiaomimimo":
            return "platform.xiaomimimo.com/session-cookie"
        case "moonshot":
            return "platform.moonshot.cn/auth_token"
        default:
            return "\(host)/system-access-token"
        }
    }

    private static func defaultRelayAdapterID(
        id: String,
        baseURL: String,
        legacyOpenConfig: OpenProviderConfig?,
        preferredAdapterID: String? = nil
    ) -> String? {
        if let preferredAdapterID = preferredAdapterID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preferredAdapterID.isEmpty {
            return preferredAdapterID
        }
        if id == "open-ailinyu" {
            return "ailinyu"
        }
        if id == "dragoncode" {
            return "dragoncode"
        }
        if id == "hongmacc" {
            return "hongmacc"
        }
        if let account = legacyOpenConfig?.accountBalance?.auth.keychainAccount?.lowercased() {
            if account.contains("open.ailinyu.de") {
                return "ailinyu"
            }
            if account.contains("dragoncode.codes") {
                return "dragoncode"
            }
            if account.contains("hongmacc.com") {
                return "hongmacc"
            }
            if account.contains("xiaomimimo.com") {
                return "xiaomimimo"
            }
            if account.contains("moonshot.cn") {
                return "moonshot"
            }
        }
        return RelayAdapterRegistry.shared.manifest(for: baseURL).id
    }

    static func normalizeRelayBaseURL(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            value = "https://open.ailinyu.de"
        }
        if !value.contains("://") {
            value = "https://" + value
        }
        if var components = URLComponents(string: value),
           let host = components.host, !host.isEmpty {
            components.path = ""
            components.query = nil
            components.fragment = nil
            components.user = nil
            components.password = nil
            components.scheme = components.scheme ?? "https"
            if var normalized = components.string {
                while normalized.hasSuffix("/") {
                    normalized.removeLast()
                }
                return normalized
            }
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private static func looksLikeGenericDefaultOverride(_ override: RelayManualOverride?) -> Bool {
        guard let override else { return true }

        func normalized(_ value: String?) -> String {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        }

        let method = normalized(override.requestMethod)
        let authHeader = normalized(override.authHeader)
        let authScheme = normalized(override.authScheme)
        let endpoint = normalized(override.endpointPath)
        let remaining = normalized(override.remainingExpression)
        let used = normalized(override.usedExpression)
        let limit = normalized(override.limitExpression)
        let success = normalized(override.successExpression)
        let unit = normalized(override.unitExpression)
        let userIDHeader = normalized(override.userIDHeader)
        let userID = normalized(override.userID)
        let body = normalized(override.requestBodyJSON)
        let accountLabel = normalized(override.accountLabelExpression)
        let staticHeadersEmpty = override.staticHeaders?.isEmpty ?? true

        let isRemainingDefault = remaining.isEmpty || remaining == "data.quota" || remaining == "div(data.quota,50000)"
        let isUsedDefault = used.isEmpty || used == "data.used_quota" || used == "div(data.used_quota,50000)"
        let isLimitDefault = limit.isEmpty || limit == "data.request_quota" || limit == "add(data.quota,data.used_quota)" || limit == "div(add(data.quota,data.used_quota),50000)"
        let isUnitDefault = unit.isEmpty || unit == "quota" || unit == "usd"

        return (method.isEmpty || method == "get") &&
            (authHeader.isEmpty || authHeader == "authorization") &&
            (authScheme.isEmpty || authScheme == "bearer") &&
            (endpoint.isEmpty || endpoint == "/api/user/self") &&
            isRemainingDefault &&
            isUsedDefault &&
            isLimitDefault &&
            (success.isEmpty || success == "success") &&
            isUnitDefault &&
            (userIDHeader.isEmpty || userIDHeader == "new-api-user") &&
            userID.isEmpty &&
            body.isEmpty &&
            accountLabel.isEmpty &&
            staticHeadersEmpty
    }

    private static func migrateGenericNewAPIDefaultOverride(_ override: RelayManualOverride?) -> RelayManualOverride? {
        guard var override else { return nil }

        func normalized(_ value: String?) -> String {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        }

        let method = normalized(override.requestMethod)
        let authHeader = normalized(override.authHeader)
        let authScheme = normalized(override.authScheme)
        let endpoint = normalized(override.endpointPath)
        let success = normalized(override.successExpression)
        let userIDHeader = normalized(override.userIDHeader)
        let remaining = normalized(override.remainingExpression)
        let used = normalized(override.usedExpression)
        let limit = normalized(override.limitExpression)
        let unit = normalized(override.unitExpression)
        let staticHeadersEmpty = override.staticHeaders?.isEmpty ?? true

        let matchesLegacyGenericNewAPI =
            (method.isEmpty || method == "get") &&
            (authHeader.isEmpty || authHeader == "authorization") &&
            (authScheme.isEmpty || authScheme == "bearer") &&
            (endpoint.isEmpty || endpoint == "/api/user/self") &&
            (success.isEmpty || success == "success") &&
            (userIDHeader.isEmpty || userIDHeader == "new-api-user") &&
            staticHeadersEmpty &&
            (remaining.isEmpty || remaining == "data.quota") &&
            (used.isEmpty || used == "data.used_quota") &&
            (limit.isEmpty || limit == "data.request_quota" || limit == "add(data.quota,data.used_quota)") &&
            (unit.isEmpty || unit == "usd" || unit == "quota")

        guard matchesLegacyGenericNewAPI else { return override }

        override.remainingExpression = "div(data.quota,50000)"
        override.usedExpression = "div(data.used_quota,50000)"
        override.limitExpression = "div(add(data.quota,data.used_quota),50000)"
        override.unitExpression = "USD"
        return override
    }

    var relayManifest: RelayAdapterManifest? {
        guard isRelay else { return nil }
        let resolvedBaseURL = relayConfig?.baseURL ?? baseURL ?? ""
        return RelayAdapterRegistry.shared.manifest(
            for: resolvedBaseURL,
            preferredID: relayConfig?.adapterID
        )
    }

    var relayDisplayMode: RelayDisplayMode {
        relayManifest?.displayMode ?? .balance
    }

    var displaysUsedQuota: Bool {
        family == .official && type == .claude && officialConfig?.quotaDisplayMode == .used
    }

    var relayViewConfig: OpenProviderConfig? {
        guard let relayConfig else { return nil }
        let manifest = relayManifest ?? RelayAdapterRegistry.shared.manifest(for: relayConfig.baseURL, preferredID: relayConfig.adapterID)
        let request = manifest.balanceRequest
        let extract = manifest.extract
        let override = relayConfig.manualOverrides
        return OpenProviderConfig(
            tokenUsageEnabled: relayConfig.tokenChannelEnabled,
            accountBalance: RelayAccountBalanceConfig(
                enabled: relayConfig.balanceChannelEnabled,
                auth: relayConfig.balanceAuth,
                authHeader: override?.authHeader ?? request.authHeader ?? "Authorization",
                authScheme: override?.authScheme ?? request.authScheme ?? "Bearer",
                requestMethod: override?.requestMethod ?? request.method,
                requestBodyJSON: override?.requestBodyJSON ?? request.bodyJSON,
                endpointPath: override?.endpointPath ?? request.path,
                userID: override?.userID ?? request.userID,
                userIDHeader: override?.userIDHeader ?? request.userIDHeader ?? "New-Api-User",
                remainingJSONPath: override?.remainingExpression ?? extract.remaining,
                usedJSONPath: override?.usedExpression ?? extract.used,
                limitJSONPath: override?.limitExpression ?? extract.limit,
                successJSONPath: override?.successExpression ?? extract.success,
                unit: override?.unitExpression ?? extract.unit ?? "quota"
            )
        )
    }

    static func defaultOfficialCodex() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "codex-official",
            name: "Official Codex",
            family: .official,
            type: .codex,
            enabled: false,
            pollIntervalSec: 120,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .localCodex),
            baseURL: "https://chatgpt.com",
            officialConfig: defaultOfficialConfig(type: .codex)
        )
    }

    static func defaultOfficialClaude() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "claude-official",
            name: "Official Claude",
            family: .official,
            type: .claude,
            enabled: false,
            pollIntervalSec: 120,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: "https://claude.ai",
            officialConfig: defaultOfficialConfig(type: .claude)
        )
    }

    static func defaultOfficialGemini() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "gemini-official",
            name: "Official Gemini",
            family: .official,
            type: .gemini,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: "https://cloudcode-pa.googleapis.com",
            officialConfig: defaultOfficialConfig(type: .gemini)
        )
    }

    static func defaultOfficialCopilot() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "copilot-official",
            name: "GitHub Copilot",
            family: .official,
            type: .copilot,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: "https://api.github.com",
            officialConfig: defaultOfficialConfig(type: .copilot)
        )
    }

    static func defaultOfficialZai() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "zai-official",
            name: "Z.ai",
            family: .official,
            type: .zai,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: "https://api.z.ai",
            officialConfig: defaultOfficialConfig(type: .zai)
        )
    }

    static func defaultOfficialAmp() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "amp-official",
            name: "Amp",
            family: .official,
            type: .amp,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: "https://ampcode.com",
            officialConfig: defaultOfficialConfig(type: .amp)
        )
    }

    static func defaultOfficialCursor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "cursor-official",
            name: "Cursor",
            family: .official,
            type: .cursor,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: "https://api2.cursor.sh",
            officialConfig: defaultOfficialConfig(type: .cursor)
        )
    }

    static func defaultOfficialJetBrains() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "jetbrains-official",
            name: "JetBrains AI Assistant",
            family: .official,
            type: .jetbrains,
            enabled: false,
            pollIntervalSec: 120,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: "file://jetbrains-local",
            officialConfig: defaultOfficialConfig(type: .jetbrains)
        )
    }

    static func defaultOfficialKiro() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "kiro-official",
            name: "Kiro",
            family: .official,
            type: .kiro,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: "cli://kiro-cli",
            officialConfig: defaultOfficialConfig(type: .kiro)
        )
    }

    static func defaultOfficialWindsurf() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "windsurf-official",
            name: "Windsurf",
            family: .official,
            type: .windsurf,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: "https://server.codeium.com",
            officialConfig: defaultOfficialConfig(type: .windsurf)
        )
    }

    static func defaultOfficialKimi() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "kimi-official",
            name: "Kimi Coding",
            family: .official,
            type: .kimi,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: "https://api.kimi.com",
            officialConfig: defaultOfficialConfig(type: .kimi)
        )
    }

    static func defaultOfficialTrae() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "trae-official",
            name: "Trae SOLO",
            family: .official,
            type: .trae,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: "official/trae/cloud-ide-jwt"
            ),
            baseURL: "https://api-sg-central.trae.ai",
            officialConfig: defaultOfficialConfig(type: .trae)
        )
    }

    static func defaultOpenAilinyu() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "open-ailinyu",
            name: "open.ailinyu.de",
            family: .thirdParty,
            type: .relay,
            enabled: false,
            pollIntervalSec: 120,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .bearer, keychainService: KeychainService.defaultServiceName, keychainAccount: "open.ailinyu.de/sk-token"),
            baseURL: "https://open.ailinyu.de",
            relayConfig: RelayProviderConfig(
                adapterID: "ailinyu",
                baseURL: "https://open.ailinyu.de",
                tokenChannelEnabled: false,
                balanceChannelEnabled: true,
                balanceAuth: AuthConfig(
                    kind: .bearer,
                    keychainService: KeychainService.defaultServiceName,
                    keychainAccount: "open.ailinyu.de/session-cookie"
                ),
                manualOverrides: RelayManualOverride(
                    authHeader: "Cookie",
                    authScheme: "",
                    userID: nil,
                    userIDHeader: "New-Api-User",
                    requestMethod: "GET",
                    requestBodyJSON: nil,
                    endpointPath: "/api/user/self",
                    remainingExpression: "data.quota",
                    usedExpression: "data.used_quota",
                    limitExpression: "data.request_quota",
                    successExpression: "success",
                    unitExpression: "quota",
                    accountLabelExpression: nil,
                    staticHeaders: nil
                )
            )
        )
    }

    static func defaultDragon() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "dragoncode",
            name: "dragoncode.codes",
            family: .thirdParty,
            type: .relay,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .bearer, keychainService: KeychainService.defaultServiceName, keychainAccount: "dragoncode.codes/auth_token"),
            baseURL: "https://dragoncode.codes",
            relayConfig: RelayProviderConfig(
                adapterID: "dragoncode",
                baseURL: "https://dragoncode.codes",
                tokenChannelEnabled: false,
                balanceChannelEnabled: true,
                balanceAuth: AuthConfig(
                    kind: .bearer,
                    keychainService: KeychainService.defaultServiceName,
                    keychainAccount: "dragoncode.codes/auth_token"
                ),
                manualOverrides: RelayManualOverride(
                    authHeader: "Authorization",
                    authScheme: "Bearer",
                    userID: nil,
                    userIDHeader: nil,
                    requestMethod: "GET",
                    requestBodyJSON: nil,
                    endpointPath: "/api/v1/auth/me",
                    remainingExpression: "data.balance",
                    usedExpression: nil,
                    limitExpression: nil,
                    successExpression: nil,
                    unitExpression: "balance",
                    accountLabelExpression: nil,
                    staticHeaders: nil
                )
            )
        )
    }

    static func defaultHongmacc() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "hongmacc",
            name: "hongmacc.com",
            family: .thirdParty,
            type: .relay,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .bearer, keychainService: KeychainService.defaultServiceName, keychainAccount: "hongmacc.com/auth_token"),
            baseURL: "https://hongmacc.com",
            relayConfig: RelayProviderConfig(
                adapterID: "hongmacc",
                baseURL: "https://hongmacc.com",
                tokenChannelEnabled: false,
                balanceChannelEnabled: true,
                balanceAuth: AuthConfig(
                    kind: .bearer,
                    keychainService: KeychainService.defaultServiceName,
                    keychainAccount: "hongmacc.com/auth_token"
                ),
                manualOverrides: RelayManualOverride(
                    authHeader: "Authorization",
                    authScheme: "Bearer",
                    userID: nil,
                    userIDHeader: nil,
                    requestMethod: "GET",
                    requestBodyJSON: nil,
                    endpointPath: "/api/user/assets",
                    remainingExpression: "sum(quotaCards.*.remainingQuota)",
                    usedExpression: nil,
                    limitExpression: nil,
                    successExpression: nil,
                    unitExpression: "CNY",
                    accountLabelExpression: nil,
                    staticHeaders: nil
                )
            )
        )
    }

    var supportedOfficialSourceModes: [OfficialSourceMode] {
        guard family == .official else { return [] }
        switch type {
        case .codex, .claude:
            return [.auto, .api, .cli, .web]
        case .kiro:
            return [.auto, .cli]
        case .gemini, .copilot, .zai, .amp, .cursor, .jetbrains, .windsurf, .kimi, .trae:
            return [.auto, .api]
        case .relay, .open, .dragon:
            return []
        }
    }

    var supportedOfficialWebModes: [OfficialWebMode] {
        guard family == .official else { return [] }
        switch type {
        case .codex, .claude:
            return [.disabled, .autoImport, .manual]
        case .gemini, .copilot, .zai, .amp, .cursor, .jetbrains, .kiro, .windsurf, .kimi, .trae:
            return [.disabled]
        case .relay, .open, .dragon:
            return []
        }
    }

    var supportsOfficialManualCookieInput: Bool {
        family == .official
            && !(officialConfig?.manualCookieAccount?.isEmpty ?? true)
            && supportedOfficialWebModes.contains(.manual)
    }
}

private extension AuthConfig {
    func withFallback(service: String, account: String?) -> AuthConfig {
        AuthConfig(
            kind: kind,
            keychainService: keychainService ?? service,
            keychainAccount: keychainAccount ?? account
        )
    }

    func normalizedCredentialServiceName() -> AuthConfig {
        let normalizedService: String?
        if let keychainService {
            let trimmed = keychainService.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == KeychainService.legacyServiceName {
                normalizedService = KeychainService.defaultServiceName
            } else {
                normalizedService = trimmed
            }
        } else {
            normalizedService = nil
        }

        return AuthConfig(
            kind: kind,
            keychainService: normalizedService,
            keychainAccount: keychainAccount
        )
    }
}

extension AppConfig {
    func migratedWithSiteDefaults() -> AppConfig {
        var migrated = self

        // Remove legacy Kimi (For Coding) provider: keep official Kimi only.
        migrated.providers.removeAll { provider in
            provider.id == "kimi-coding" || (provider.type == .kimi && provider.family == .thirdParty)
        }

        for defaultProvider in AppConfig.default.providers {
            if let idx = migrated.providers.firstIndex(where: { $0.id == defaultProvider.id }) {
                migrated.providers[idx] = migrated.providers[idx].migratedSiteDefaults(from: defaultProvider)
            } else {
                migrated.providers.append(defaultProvider)
            }
        }

        for idx in migrated.providers.indices {
            let providerID = migrated.providers[idx].id
            guard providerID == "codex-official" || providerID == "claude-official" else {
                continue
            }
            // Only migrate historical defaults; keep user-custom intervals untouched.
            if migrated.providers[idx].pollIntervalSec == 60 {
                migrated.providers[idx].pollIntervalSec = 120
            }
        }

        if let selected = migrated.statusBarProviderID,
           migrated.providers.contains(where: { $0.id == selected }) == false {
            migrated.statusBarProviderID = AppConfig.defaultStatusBarProviderID(from: migrated.providers)
        }
        if migrated.statusBarProviderID == nil {
            migrated.statusBarProviderID = AppConfig.defaultStatusBarProviderID(from: migrated.providers)
        }
        migrated.statusBarMultiProviderIDs = AppConfig.normalizedStatusBarMultiProviderIDs(
            migrated.statusBarMultiProviderIDs,
            providers: migrated.providers
        )
        if migrated.statusBarMultiProviderIDs.isEmpty,
           let selected = migrated.statusBarProviderID {
            migrated.statusBarMultiProviderIDs = [selected]
        }

        return migrated
    }
}

private extension ProviderDescriptor {
    func migratedSiteDefaults(from defaults: ProviderDescriptor) -> ProviderDescriptor {
        var copy = self

        copy.family = defaults.family

        if (copy.baseURL ?? "").isEmpty {
            copy.baseURL = defaults.baseURL
        }

        if defaults.family == .official {
            if copy.officialConfig == nil {
                copy.officialConfig = defaults.officialConfig
            } else {
                if var official = copy.officialConfig {
                    let manualCookieAccount = official.manualCookieAccount
                    official.manualCookieAccount = manualCookieAccount ?? defaults.officialConfig?.manualCookieAccount
                    copy.officialConfig = official
                }
            }
            if copy.pollIntervalSec <= 0 {
                copy.pollIntervalSec = defaults.pollIntervalSec
            }
            return copy.normalized()
        }

        if copy.type == .kimi {
            if copy.kimiConfig == nil {
                copy.kimiConfig = defaults.kimiConfig
            } else if copy.kimiConfig?.browserOrder.isEmpty ?? true {
                copy.kimiConfig?.browserOrder = defaults.kimiConfig?.browserOrder
                    ?? [.arc, .chrome, .safari, .edge, .brave, .firefox, .opera, .operaGX, .vivaldi, .chromium]
            }
            return copy.normalized()
        }

        guard copy.isRelay,
              let defaultRelay = defaults.relayConfig else {
            return copy.normalized()
        }

        if copy.relayConfig == nil {
            copy.relayConfig = defaultRelay
            return copy.normalized()
        }

        guard var relay = copy.relayConfig else {
            return copy.normalized()
        }

        if copy.id == "open-ailinyu" {
            if copy.pollIntervalSec < 120 {
                copy.pollIntervalSec = 120
            }
        }

        relay.adapterID = relay.adapterID ?? defaultRelay.adapterID
        relay.baseURL = ProviderDescriptor.normalizeRelayBaseURL(
            relay.baseURL.isEmpty ? (copy.baseURL ?? defaults.baseURL ?? defaultRelay.baseURL) : relay.baseURL
        )
        relay.balanceAuth = relay.balanceAuth.withFallback(
            service: defaultRelay.balanceAuth.keychainService ?? KeychainService.defaultServiceName,
            account: defaultRelay.balanceAuth.keychainAccount
        )
        if relay.manualOverrides == nil {
            relay.manualOverrides = defaultRelay.manualOverrides
        }
        copy.relayConfig = relay
        return copy.normalized()
    }
}
