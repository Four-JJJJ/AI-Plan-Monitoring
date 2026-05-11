import XCTest
@testable import OhMyUsage

final class ProviderFactoryTests: XCTestCase {
    func testTraeProviderUsesInjectedBrowserCredentialService() throws {
        let browserCredentialService = BrowserCredentialService(
            bearerCandidatesOverride: { _ in [] },
            cacheTTL: 0
        )
        let factory = ProviderFactory(
            keychain: makeTestKeychain(),
            browserCredentialService: browserCredentialService
        )

        let provider = try XCTUnwrap(factory.makeProvider(for: ProviderDescriptor.defaultOfficialTrae()) as? TraeProvider)
        XCTAssertTrue(provider.browserCredentialService === browserCredentialService)
    }
}
