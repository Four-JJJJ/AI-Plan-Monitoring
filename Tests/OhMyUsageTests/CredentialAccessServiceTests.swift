import Foundation
import XCTest
@testable import OhMyUsage

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

    func testDisplayOnlyMissingCredentialDoesNotScheduleLookup() {
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

        XCTAssertNil(
            service.savedCredentialLength(
                service: "svc",
                account: "missing",
                secureStorageReady: true,
                onLookupStateChanged: {}
            )
        )
        XCTAssertEqual(service.debugMissingKeyCount, 0)
        XCTAssertEqual(service.debugLookupInFlightCount, 0)
    }

    func testDisplayOnlyLookupDoesNotReadSecureStoreWhenCacheMiss() {
        let suite = "CredentialAccessServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let recorder = CredentialReadRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, _ in
                recorder.recordReadData(service: service, account: account)
                return Data("secret-token".utf8)
            },
            readAll: { service, _ in
                recorder.recordReadAll(service: service)
                return ["acct": "secret-token"]
            },
            saveData: { _, _, _, _ in true },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )

        let keychain = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )
        let service = CredentialAccessService(keychain: keychain)

        XCTAssertNil(
            service.savedCredentialLength(
                service: "svc",
                account: "acct",
                secureStorageReady: true,
                onLookupStateChanged: {}
            )
        )
        XCTAssertEqual(recorder.counts.readData, 0)
        XCTAssertEqual(recorder.counts.readAll, 0)
        XCTAssertEqual(service.debugLookupInFlightCount, 0)
    }

    func testDisplayOnlyLengthUsesSavedMetadataWithoutReadingSecureStore() {
        let suite = "CredentialAccessServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let recorder = CredentialReadRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, _ in
                recorder.recordReadData(service: service, account: account)
                return nil
            },
            readAll: { service, _ in
                recorder.recordReadAll(service: service)
                return nil
            },
            saveData: { _, _, _, _ in true },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )

        let savingKeychain = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )
        XCTAssertTrue(savingKeychain.saveToken("secret-token", service: "svc", account: "acct"))

        let displayOnlyKeychain = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )
        let service = CredentialAccessService(keychain: displayOnlyKeychain)

        XCTAssertEqual(
            service.savedCredentialLength(
                service: "svc",
                account: "acct",
                secureStorageReady: true,
                onLookupStateChanged: {}
            ),
            "secret-token".count
        )
        XCTAssertEqual(recorder.counts.readData, 0)
        XCTAssertEqual(recorder.counts.readAll, 0)
    }

    private func makeCredentialURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CredentialAccessServiceTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("credentials.json")
    }
}

private final class CredentialReadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var readDataCount = 0
    private var readAllCount = 0

    var counts: (readData: Int, readAll: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (readDataCount, readAllCount)
    }

    func recordReadData(service: String, account: String) {
        _ = service
        _ = account
        lock.lock()
        readDataCount += 1
        lock.unlock()
    }

    func recordReadAll(service: String) {
        _ = service
        lock.lock()
        readAllCount += 1
        lock.unlock()
    }
}
