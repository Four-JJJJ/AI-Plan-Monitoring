import Foundation
import OhMyUsageDomain

struct ProviderFactoryRegistry {
    struct Dependencies {
        let keychain: KeychainService
        let kimiCookieService: KimiBrowserCookieService
        let browserCookieService: BrowserCookieService
        let browserCredentialService: BrowserCredentialService
    }

    typealias Maker = (ProviderDescriptor, Dependencies) -> UsageProvider

    private let makers: [ProviderType: Maker]

    init(makers: [ProviderType: Maker] = Self.makeDefaultMakers()) {
        self.makers = makers
        precondition(
            Set(makers.keys) == Set(ProviderType.allCases),
            "ProviderFactoryRegistry must register every ProviderType"
        )
    }

    var registeredProviderTypes: Set<ProviderType> {
        Set(makers.keys)
    }

    func makeProvider(
        for descriptor: ProviderDescriptor,
        dependencies: Dependencies
    ) -> UsageProvider {
        guard let maker = makers[descriptor.type] else {
            preconditionFailure("Missing provider maker for \(descriptor.type)")
        }
        return maker(descriptor, dependencies)
    }

    private static func makeDefaultMakers() -> [ProviderType: Maker] {
        [
            .codex: { descriptor, dependencies in
                CodexProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCookieService: dependencies.browserCookieService
                )
            },
            .claude: { descriptor, dependencies in
                ClaudeProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCookieService: dependencies.browserCookieService
                )
            },
            .gemini: { descriptor, _ in
                GeminiProvider(descriptor: descriptor)
            },
            .copilot: { descriptor, _ in
                CopilotProvider(descriptor: descriptor)
            },
            .microsoftCopilot: { descriptor, _ in
                MicrosoftCopilotProvider(descriptor: descriptor)
            },
            .zai: { descriptor, _ in
                ZaiProvider(descriptor: descriptor)
            },
            .amp: { descriptor, _ in
                AmpProvider(descriptor: descriptor)
            },
            .cursor: { descriptor, _ in
                CursorProvider(descriptor: descriptor)
            },
            .jetbrains: { descriptor, _ in
                JetBrainsProvider(descriptor: descriptor)
            },
            .kiro: { descriptor, _ in
                KiroProvider(descriptor: descriptor)
            },
            .windsurf: { descriptor, _ in
                WindsurfProvider(descriptor: descriptor)
            },
            .trae: { descriptor, dependencies in
                TraeProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCredentialService: dependencies.browserCredentialService
                )
            },
            .openrouterCredits: { descriptor, dependencies in
                OpenRouterProvider(descriptor: descriptor, keychain: dependencies.keychain)
            },
            .openrouterAPI: { descriptor, dependencies in
                OpenRouterProvider(descriptor: descriptor, keychain: dependencies.keychain)
            },
            .ollamaCloud: { descriptor, dependencies in
                OllamaCloudProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCookieService: dependencies.browserCookieService
                )
            },
            .opencodeGo: { descriptor, dependencies in
                OpenCodeGoProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCookieService: dependencies.browserCookieService
                )
            },
            .relay: ProviderFactoryRegistry.makeRelayProvider,
            .open: ProviderFactoryRegistry.makeRelayProvider,
            .dragon: ProviderFactoryRegistry.makeRelayProvider,
            .kimi: { descriptor, dependencies in
                KimiSmartProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCookieService: dependencies.kimiCookieService
                )
            }
        ]
    }

    private static func makeRelayProvider(
        descriptor: ProviderDescriptor,
        dependencies: Dependencies
    ) -> UsageProvider {
        RelayProvider(
            descriptor: descriptor,
            keychain: dependencies.keychain,
            browserCredentialService: dependencies.browserCredentialService
        )
    }
}
