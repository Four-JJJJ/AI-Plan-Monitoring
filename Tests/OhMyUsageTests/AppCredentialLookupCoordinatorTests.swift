import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

@MainActor
final class AppCredentialLookupCoordinatorTests: XCTestCase {
    func testDescriptorCredentialLookupUsesSavedMetadata() {
        let coordinator = AppCredentialLookupCoordinator()
        let service = CredentialAccessService(keychain: KeychainService(storageURL: makeCredentialURL()))
        var descriptor = ProviderDescriptor.defaultOpenAilinyu()
        descriptor.auth = AuthConfig(
            kind: .bearer,
            keychainService: "svc",
            keychainAccount: "acct"
        )

        XCTAssertTrue(service.saveCredential("secret-token", service: "svc", account: "acct"))

        XCTAssertTrue(coordinator.credentialExists(
            for: descriptor,
            secureStorageReady: true,
            lookupVersion: 0,
            credentialAccessService: service,
            onLookupStateChanged: {}
        ))
        XCTAssertEqual(coordinator.savedCredentialLength(
            for: descriptor,
            secureStorageReady: true,
            lookupVersion: 0,
            credentialAccessService: service,
            onLookupStateChanged: {}
        ), "secret-token".count)
    }

    func testAuthLookupReturnsFalseForMissingKeychainIdentity() {
        let coordinator = AppCredentialLookupCoordinator()
        let service = CredentialAccessService(keychain: KeychainService(storageURL: makeCredentialURL()))
        let auth = AuthConfig(kind: .bearer)

        XCTAssertFalse(coordinator.credentialExists(
            auth: auth,
            secureStorageReady: true,
            lookupVersion: 0,
            credentialAccessService: service,
            onLookupStateChanged: {}
        ))
        XCTAssertNil(coordinator.savedCredentialLength(
            auth: auth,
            secureStorageReady: true,
            lookupVersion: 0,
            credentialAccessService: service,
            onLookupStateChanged: {}
        ))
    }

    func testManualCookieLookupRequiresOfficialProviderWithCookieAccount() {
        let coordinator = AppCredentialLookupCoordinator()
        let service = CredentialAccessService(keychain: KeychainService(storageURL: makeCredentialURL()))
        var official = ProviderDescriptor.defaultOfficialCodex()
        official.officialConfig?.manualCookieAccount = "official/codex/test-cookie"
        let relay = ProviderDescriptor.defaultOpenAilinyu()

        XCTAssertTrue(service.saveCredential(
            "cookie-value",
            service: KeychainService.defaultServiceName,
            account: "official/codex/test-cookie"
        ))

        XCTAssertTrue(coordinator.manualCookieExists(
            for: official,
            secureStorageReady: true,
            lookupVersion: 0,
            credentialAccessService: service,
            onLookupStateChanged: {}
        ))
        XCTAssertEqual(coordinator.savedManualCookieLength(
            for: official,
            secureStorageReady: true,
            lookupVersion: 0,
            credentialAccessService: service,
            onLookupStateChanged: {}
        ), "cookie-value".count)
        XCTAssertFalse(coordinator.manualCookieExists(
            for: relay,
            secureStorageReady: true,
            lookupVersion: 0,
            credentialAccessService: service,
            onLookupStateChanged: {}
        ))
        XCTAssertNil(coordinator.savedManualCookieLength(
            for: relay,
            secureStorageReady: true,
            lookupVersion: 0,
            credentialAccessService: service,
            onLookupStateChanged: {}
        ))
    }

    private func makeCredentialURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AppCredentialLookupCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("credentials.json")
    }
}
