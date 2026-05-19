import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class AppProviderCredentialCoordinatorTests: XCTestCase {
    func testSaveTokenNormalizesAndPersistsCredential() {
        let coordinator = AppProviderCredentialCoordinator()
        var descriptor = ProviderDescriptor.defaultOpenAilinyu()
        descriptor.auth = AuthConfig(
            kind: .bearer,
            keychainService: "service",
            keychainAccount: "account"
        )
        var captured: (value: String, service: String, account: String)?

        let outcome = coordinator.saveToken(
            " token ",
            descriptor: descriptor,
            normalize: { token, _ in token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() },
            saveCredential: { value, service, account in
                captured = (value, service, account)
                return true
            }
        )

        XCTAssertEqual(captured?.value, "TOKEN")
        XCTAssertEqual(captured?.service, "service")
        XCTAssertEqual(captured?.account, "account")
        XCTAssertEqual(
            outcome,
            AppCredentialMutationOutcome(
                didPersistCredential: true,
                shouldBumpLookupVersion: true
            )
        )
    }

    func testSaveOfficialManualCookieRejectsBlankInput() {
        let coordinator = AppProviderCredentialCoordinator()
        let providers = [ProviderDescriptor.defaultOfficialOllamaCloud()]

        let outcome = coordinator.saveOfficialManualCookie(
            "   ",
            providerID: providers[0].id,
            providers: providers,
            saveCredential: { _, _, _ in
                XCTFail("blank input should not persist")
                return false
            }
        )

        XCTAssertEqual(outcome, .none)
    }

    func testInvalidateLookupCacheRequestsVersionBump() {
        let coordinator = AppProviderCredentialCoordinator()
        var invalidated = false

        let outcome = coordinator.invalidateLookupCache {
            invalidated = true
        }

        XCTAssertTrue(invalidated)
        XCTAssertEqual(
            outcome,
            AppCredentialMutationOutcome(
                didPersistCredential: false,
                shouldBumpLookupVersion: true
            )
        )
    }
}
