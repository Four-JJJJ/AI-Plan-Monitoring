import Foundation

final class ProviderFactory {
    private let keychain: KeychainService
    private let kimiCookieService: KimiBrowserCookieService
    private let browserCookieService: BrowserCookieService
    private let browserCredentialService: BrowserCredentialService

    init(
        keychain: KeychainService,
        kimiCookieService: KimiBrowserCookieService = KimiBrowserCookieService(),
        browserCookieService: BrowserCookieService = BrowserCookieService()
    ) {
        self.keychain = keychain
        self.kimiCookieService = kimiCookieService
        self.browserCookieService = browserCookieService
        self.browserCredentialService = BrowserCredentialService(
            bearerService: kimiCookieService,
            cookieService: browserCookieService
        )
    }

    func makeProvider(for descriptor: ProviderDescriptor) -> UsageProvider {
        switch descriptor.type {
        case .codex:
            return CodexProvider(descriptor: descriptor, keychain: keychain, browserCookieService: browserCookieService)
        case .claude:
            return ClaudeProvider(descriptor: descriptor, keychain: keychain, browserCookieService: browserCookieService)
        case .gemini:
            return GeminiProvider(descriptor: descriptor)
        case .copilot:
            return CopilotProvider(descriptor: descriptor)
        case .microsoftCopilot:
            return MicrosoftCopilotProvider(descriptor: descriptor)
        case .zai:
            return ZaiProvider(descriptor: descriptor)
        case .amp:
            return AmpProvider(descriptor: descriptor)
        case .cursor:
            return CursorProvider(descriptor: descriptor)
        case .jetbrains:
            return JetBrainsProvider(descriptor: descriptor)
        case .kiro:
            return KiroProvider(descriptor: descriptor)
        case .windsurf:
            return WindsurfProvider(descriptor: descriptor)
        case .trae:
            return TraeProvider(descriptor: descriptor, keychain: keychain)
        case .openrouterCredits, .openrouterAPI:
            return OpenRouterProvider(descriptor: descriptor, keychain: keychain)
        case .ollamaCloud:
            return OllamaCloudProvider(
                descriptor: descriptor,
                keychain: keychain,
                browserCookieService: browserCookieService
            )
        case .opencodeGo:
            return OpenCodeGoProvider(
                descriptor: descriptor,
                keychain: keychain,
                browserCookieService: browserCookieService
            )
        case .relay, .open, .dragon:
            return RelayProvider(
                descriptor: descriptor,
                keychain: keychain,
                browserCredentialService: browserCredentialService
            )
        case .kimi:
            return KimiSmartProvider(
                descriptor: descriptor,
                keychain: keychain,
                browserCookieService: kimiCookieService
            )
        }
    }
}
