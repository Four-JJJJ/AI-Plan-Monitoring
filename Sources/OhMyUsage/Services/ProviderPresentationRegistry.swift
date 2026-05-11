import Foundation

struct ProviderCapabilities: Equatable, Sendable {
    var supportsBalance: Bool
    var supportsQuotaWindows: Bool
    var supportsAccountSwitching: Bool
    var supportsLocalUsageHistory: Bool
    var usesPercentageMenuCard: Bool

    static func capabilities(for provider: ProviderDescriptor) -> ProviderCapabilities {
        ProviderCapabilities(
            supportsBalance: provider.isRelay || provider.family == .thirdParty || provider.type == .openrouterCredits,
            supportsQuotaWindows: provider.family == .official || provider.relayDisplayMode == .quotaPercent,
            supportsAccountSwitching: provider.family == .official && (provider.type == .codex || provider.type == .claude),
            supportsLocalUsageHistory: provider.family == .official && (provider.type == .codex || provider.type == .claude || provider.type == .kimi),
            usesPercentageMenuCard: provider.family == .official || provider.type == .kimi || provider.relayDisplayMode == .quotaPercent
        )
    }
}

struct ProviderPresentation: Equatable, Sendable {
    var displayName: String
    var iconName: String
    var fallbackSystemIcon: String
}

enum ProviderPresentationRegistry {
    static func presentation(for provider: ProviderDescriptor?) -> ProviderPresentation {
        ProviderPresentation(
            displayName: displayName(for: provider),
            iconName: iconName(for: provider),
            fallbackSystemIcon: fallbackIcon(for: provider)
        )
    }

    static func displayName(for provider: ProviderDescriptor?) -> String {
        guard let provider else { return "第三方中转站" }
        switch provider.type {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        case .gemini:
            return "Gemini"
        case .copilot:
            return "GitHub Copilot"
        case .microsoftCopilot:
            return "Microsoft Copilot"
        case .zai:
            return "Z.ai"
        case .amp:
            return "Amp"
        case .cursor:
            return "Cursor"
        case .jetbrains:
            return "JetBrains"
        case .kiro:
            return "Kiro"
        case .windsurf:
            return "Windsurf"
        case .kimi:
            return provider.family == .official ? "Kimi Coding" : "KIMI"
        case .trae:
            return "Trae SOLO"
        case .openrouterCredits:
            return "OpenRouter Credits"
        case .openrouterAPI:
            return "OpenRouter API"
        case .ollamaCloud:
            return "Ollama Cloud"
        case .opencodeGo:
            return "OpenCode Go"
        case .relay, .open, .dragon:
            if provider.isOfficialRelayProvider,
               let adapterID = provider.officialRelayAdapterID,
               let displayName = ProviderDescriptor.officialRelayDisplayName(adapterID: adapterID) {
                return displayName
            }
            return provider.name
        }
    }

    static func iconName(for provider: ProviderDescriptor?) -> String {
        guard let provider else { return "menu_relay_icon" }
        switch provider.type {
        case .codex:
            return "menu_codex_icon"
        case .claude:
            return "menu_claude_icon"
        case .gemini:
            return "menu_gemini_icon"
        case .copilot:
            return "menu_github_copilot_icon"
        case .microsoftCopilot:
            return "menu_microsoft_copilot_icon"
        case .zai:
            return "menu_zai_icon"
        case .amp:
            return "menu_amp_icon"
        case .cursor:
            return "menu_cursor_icon"
        case .jetbrains:
            return "menu_jetbrains_icon"
        case .kiro:
            return "menu_kiro_icon"
        case .windsurf:
            return "menu_windsurf_icon"
        case .kimi:
            return "menu_kimi_icon"
        case .trae:
            return "menu_relay_icon"
        case .openrouterCredits, .openrouterAPI:
            return "menu_openrouter_icon"
        case .ollamaCloud:
            return "menu_ollama_icon"
        case .opencodeGo:
            return "menu_opencode_icon"
        case .relay, .open, .dragon:
            if provider.isOfficialRelayProvider,
               let adapterID = provider.officialRelayAdapterID,
               let iconName = ProviderDescriptor.officialRelayIconName(adapterID: adapterID) {
                return iconName
            }
            return relayIconOverrideName(for: provider) ?? "menu_relay_icon"
        }
    }

    static func fallbackIcon(for provider: ProviderDescriptor?) -> String {
        guard let provider else { return "link" }
        switch provider.type {
        case .codex:
            return "terminal.fill"
        case .kimi:
            return "moon.stars.fill"
        case .trae, .openrouterCredits, .openrouterAPI, .ollamaCloud, .opencodeGo, .relay, .open, .dragon:
            return "link"
        case .claude, .gemini:
            return "sparkles"
        case .copilot:
            return "chevron.left.forwardslash.chevron.right"
        case .microsoftCopilot:
            return "building.2.crop.circle"
        case .zai:
            return "z.square.fill"
        case .amp:
            return "bolt.fill"
        case .cursor:
            return "cursorarrow.rays"
        case .jetbrains:
            return "brain.head.profile"
        case .kiro:
            return "wand.and.stars.inverse"
        case .windsurf:
            return "wind"
        }
    }

    private static func relayIconOverrideName(for provider: ProviderDescriptor) -> String? {
        guard provider.type == .relay || provider.type == .open || provider.type == .dragon else {
            return nil
        }
        let relayID = (provider.relayConfig?.adapterID ?? provider.relayManifest?.id ?? "").lowercased()
        let relayBaseURL = provider.relayConfig?.baseURL ?? provider.baseURL ?? ""
        let host = URL(string: relayBaseURL)?.host?.lowercased() ?? ""
        let providerName = provider.name.lowercased()
        let relaySignals = "\(relayID)|\(host)|\(providerName)"
        if relaySignals.contains("moonshot") || relaySignals.contains("moonsho") || relaySignals.contains("kimi") {
            return "menu_kimi_icon"
        }
        if relaySignals.contains("deepseek") {
            return firstExistingRelayIconName(["menu_deepseek_icon", "menu_deep_seek_icon"])
        }
        if relaySignals.contains("xiaomimimo") || relaySignals.contains("mimo") {
            return firstExistingRelayIconName(["menu_mimo_icon", "menu_xiaomimimo_icon", "menu_xiaomi_mimo_icon"])
        }
        if relaySignals.contains("minimax") || relaySignals.contains("minimaxi") {
            return firstExistingRelayIconName(["menu_minimax_icon", "menu_minimaxi_icon"])
        }
        return nil
    }

    private static func firstExistingRelayIconName(_ candidates: [String]) -> String? {
        for name in candidates {
            if Bundle.module.url(forResource: name, withExtension: "png") != nil ||
                Bundle.module.url(forResource: name, withExtension: "svg") != nil {
                return name
            }
        }
        return nil
    }
}

enum QuotaMetricDisplayFactory {
    static func preferredMetricCount(for provider: ProviderDescriptor) -> Int {
        provider.type == .claude ? 4 : 2
    }
}
