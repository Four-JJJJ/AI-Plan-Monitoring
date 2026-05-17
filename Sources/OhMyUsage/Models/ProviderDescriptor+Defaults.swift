import Foundation

extension ProviderDescriptor {
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

    static func defaultOfficialMicrosoftCopilot() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "microsoft-copilot-official",
            name: "Microsoft Copilot",
            family: .official,
            type: .microsoftCopilot,
            enabled: false,
            pollIntervalSec: 120,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: "https://graph.microsoft.com",
            officialConfig: defaultOfficialConfig(type: .microsoftCopilot)
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

    static func defaultOfficialOpenRouterCredits() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "openrouter-credits-official",
            name: "OpenRouter Credits",
            family: .official,
            type: .openrouterCredits,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: "official/openrouter/credits-api-key"
            ),
            baseURL: "https://openrouter.ai/api/v1",
            officialConfig: defaultOfficialConfig(type: .openrouterCredits)
        )
    }

    static func defaultOfficialOpenRouterAPI() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "openrouter-api-official",
            name: "OpenRouter API",
            family: .official,
            type: .openrouterAPI,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: "official/openrouter/api-key"
            ),
            baseURL: "https://openrouter.ai/api/v1",
            officialConfig: defaultOfficialConfig(type: .openrouterAPI)
        )
    }

    static func defaultOfficialOllamaCloud() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "ollama-cloud-official",
            name: "Ollama Cloud",
            family: .official,
            type: .ollamaCloud,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: "https://ollama.com",
            officialConfig: defaultOfficialConfig(type: .ollamaCloud)
        )
    }

    static func defaultOfficialOpenCodeGo() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "opencode-go-official",
            name: "OpenCode Go",
            family: .official,
            type: .opencodeGo,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(
                kind: .none,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: "official/opencode-go/workspace-id"
            ),
            baseURL: "https://opencode.ai",
            officialConfig: defaultOfficialConfig(type: .opencodeGo)
        )
    }

    private static func defaultOfficialRelaySite(
        metadata: OfficialRelayMetadata
    ) -> ProviderDescriptor {
        let auth = AuthConfig(
            kind: .bearer,
            keychainService: KeychainService.defaultServiceName,
            keychainAccount: metadata.keychainAccount
        )
        return ProviderDescriptor(
            id: metadata.providerID,
            name: metadata.displayName,
            family: .official,
            type: .relay,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: auth,
            baseURL: metadata.baseURL,
            relayConfig: defaultRelayConfig(
                id: metadata.providerID,
                baseURL: metadata.baseURL,
                preferredAdapterID: metadata.defaultAdapterID,
                auth: auth
            )
        )
        .normalized()
    }

    private static func defaultOfficialRelaySite(providerID: String) -> ProviderDescriptor {
        guard let metadata = OfficialRelayMetadataCatalog.metadata(forProviderID: providerID) else {
            preconditionFailure("Missing official relay metadata for \(providerID)")
        }
        return defaultOfficialRelaySite(metadata: metadata)
    }

    static func defaultOfficialMoonshot() -> ProviderDescriptor {
        defaultOfficialRelaySite(providerID: "moonshot-official")
    }

    static func defaultOfficialMiniMax() -> ProviderDescriptor {
        defaultOfficialRelaySite(providerID: "minimax-official")
    }

    static func defaultOfficialDeepSeek() -> ProviderDescriptor {
        defaultOfficialRelaySite(providerID: "deepseek-official")
    }

    static func defaultOfficialXiaomiMIMO() -> ProviderDescriptor {
        defaultOfficialRelaySite(providerID: "xiaomi-mimo-official")
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

}
