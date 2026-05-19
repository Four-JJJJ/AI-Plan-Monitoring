import Foundation
import OhMyUsageDomain

extension ProviderDescriptor {
    static func defaultOfficialCodex() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.codex()
    }

    static func defaultOfficialClaude() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.claude()
    }

    static func defaultOfficialGemini() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.gemini()
    }

    static func defaultOfficialCopilot() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.copilot()
    }

    static func defaultOfficialMicrosoftCopilot() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.microsoftCopilot()
    }

    static func defaultOfficialZai() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.zai()
    }

    static func defaultOfficialAmp() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.amp()
    }

    static func defaultOfficialCursor() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.cursor()
    }

    static func defaultOfficialJetBrains() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.jetBrains()
    }

    static func defaultOfficialKiro() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.kiro()
    }

    static func defaultOfficialWindsurf() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.windsurf()
    }

    static func defaultOfficialKimi() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.kimi()
    }

    static func defaultOfficialMoonshot() -> ProviderDescriptor {
        OfficialRelayProviderDefaultCatalog.moonshot()
    }

    static func defaultOfficialMiniMax() -> ProviderDescriptor {
        OfficialRelayProviderDefaultCatalog.miniMax()
    }

    static func defaultOfficialDeepSeek() -> ProviderDescriptor {
        OfficialRelayProviderDefaultCatalog.deepSeek()
    }

    static func defaultOfficialXiaomiMIMO() -> ProviderDescriptor {
        OfficialRelayProviderDefaultCatalog.xiaomiMIMO()
    }

    static func defaultOfficialTrae() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.trae()
    }

    static func defaultOfficialOpenRouterCredits() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.openRouterCredits()
    }

    static func defaultOfficialOpenRouterAPI() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.openRouterAPI()
    }

    static func defaultOfficialOllamaCloud() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.ollamaCloud()
    }

    static func defaultOfficialOpenCodeGo() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.openCodeGo()
    }

    static func defaultOpenAilinyu() -> ProviderDescriptor {
        RelayProviderDefaultCatalog.defaultOpenAilinyu()
    }
}
