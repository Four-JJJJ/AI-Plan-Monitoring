import Foundation

extension ProviderDescriptor {
    static func defaultOfficialBaseURL(type: ProviderType) -> String {
        switch type {
        case .codex:
            return "https://chatgpt.com"
        case .claude:
            return "https://claude.ai"
        case .gemini:
            return "https://cloudcode-pa.googleapis.com"
        case .copilot:
            return "https://api.github.com"
        case .microsoftCopilot:
            return "https://graph.microsoft.com"
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
        case .openrouterCredits, .openrouterAPI:
            return "https://openrouter.ai/api/v1"
        case .ollamaCloud:
            return "https://ollama.com"
        case .opencodeGo:
            return "https://opencode.ai"
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
                oauthAccountImportEnabled: true,
                autoDiscoveryEnabled: true
            )
        case .claude:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .autoImport,
                manualCookieAccount: "official/claude/cookie-header",
                oauthAccountImportEnabled: false,
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
        case .microsoftCopilot:
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
                autoDiscoveryEnabled: true,
                traeValueDisplayMode: .percent
            )
        case .openrouterCredits, .openrouterAPI:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .disabled,
                manualCookieAccount: nil,
                autoDiscoveryEnabled: true
            )
        case .ollamaCloud:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .autoImport,
                manualCookieAccount: "official/ollama/session-cookie",
                autoDiscoveryEnabled: true
            )
        case .opencodeGo:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .autoImport,
                manualCookieAccount: "official/opencode-go/auth-cookie",
                autoDiscoveryEnabled: true
            )
        case .relay, .open, .dragon:
            return OfficialProviderConfig()
        }
    }

    static func defaultKimiConfig(auth: AuthConfig) -> KimiProviderConfig {
        KimiProviderConfig(
            authMode: .auto,
            manualTokenAccount: auth.keychainAccount ?? "kimi.com/kimi-auth-manual",
            autoCookieEnabled: true,
            browserOrder: [.arc, .chrome, .safari, .edge, .brave, .firefox, .opera, .operaGX, .vivaldi, .chromium]
        )
    }
}
