import Foundation
import XCTest
@testable import AIPlanMonitor

@MainActor
final class CredentialAccessServiceTests: XCTestCase {
    func testSaveCredentialMakesLengthAvailableFromCache() {
        let keychain = KeychainService(storageURL: makeCredentialURL())
        let service = CredentialAccessService(keychain: keychain)

        XCTAssertTrue(service.saveCredential("secret-token", service: "svc", account: "acct"))

        let length = service.savedCredentialLength(
            service: "svc",
            account: "acct",
            secureStorageReady: true,
            onLookupStateChanged: {}
        )
        XCTAssertEqual(length, "secret-token".count)
    }

    func testMissingCredentialLookupIsNotRepeatedAfterMiss() async throws {
        let keychain = KeychainService(storageURL: makeCredentialURL())
        let service = CredentialAccessService(keychain: keychain)

        XCTAssertNil(
            service.savedCredentialLength(
                service: "svc",
                account: "missing",
                secureStorageReady: true,
                onLookupStateChanged: {}
            )
        )

        try await waitUntil {
            service.debugMissingKeyCount == 1 && service.debugLookupInFlightCount == 0
        }

        XCTAssertNil(
            service.savedCredentialLength(
                service: "svc",
                account: "missing",
                secureStorageReady: true,
                onLookupStateChanged: {}
            )
        )
        XCTAssertEqual(service.debugMissingKeyCount, 1)
        XCTAssertEqual(service.debugLookupInFlightCount, 0)
    }

    private func makeCredentialURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CredentialAccessServiceTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("credentials.json")
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        predicate: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for credential lookup state")
    }
}
