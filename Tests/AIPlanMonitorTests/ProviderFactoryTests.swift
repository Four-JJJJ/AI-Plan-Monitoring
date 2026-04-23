import XCTest
@testable import AIPlanMonitor

final class ProviderFactoryTests: XCTestCase {
    func testTraeProviderUsesInjectedBrowserCredentialService() throws {
        let browserCredentialService = BrowserCredentialService(
            bearerCandidatesOverride: { _ in [] },
            cacheTTL: 0
        )
        let factory = ProviderFactory(
            keychain: KeychainService(),
            browserCredentialService: browserCredentialService
        )

        let provider = try XCTUnwrap(factory.makeProvider(for: ProviderDescriptor.defaultOfficialTrae()) as? TraeProvider)
        XCTAssertTrue(provider.browserCredentialService === browserCredentialService)
    }
}
