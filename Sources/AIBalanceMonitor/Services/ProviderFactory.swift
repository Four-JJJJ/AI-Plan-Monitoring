import Foundation

final class ProviderFactory {
    private let keychain: KeychainService
    private let kimiCookieService: KimiBrowserCookieService

    init(keychain: KeychainService, kimiCookieService: KimiBrowserCookieService = KimiBrowserCookieService()) {
        self.keychain = keychain
        self.kimiCookieService = kimiCookieService
    }

    func makeProvider(for descriptor: ProviderDescriptor) -> UsageProvider {
        switch descriptor.type {
        case .codex:
            return CodexProvider(descriptor: descriptor)
        case .open:
            return OpenProvider(descriptor: descriptor, keychain: keychain)
        case .dragon:
            return OpenProvider(descriptor: descriptor, keychain: keychain)
        case .kimi:
            return KimiProvider(descriptor: descriptor, keychain: keychain, browserCookieService: kimiCookieService)
        }
    }
}
