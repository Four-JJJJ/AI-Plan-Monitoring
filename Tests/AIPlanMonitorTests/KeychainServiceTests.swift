import XCTest
@testable import AIPlanMonitor

final class KeychainServiceTests: XCTestCase {
    func testLegacyServiceNameIsNormalizedToAIPlanMonitor() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("credentials.json")
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = KeychainService(storageURL: tempURL)
        XCTAssertTrue(store.saveToken("secret", service: KeychainService.legacyServiceName, account: "demo"))

        let reloaded = KeychainService(storageURL: tempURL)
        XCTAssertEqual(reloaded.readToken(service: KeychainService.defaultServiceName, account: "demo"), "secret")
        XCTAssertEqual(reloaded.readToken(service: KeychainService.legacyServiceName, account: "demo"), "secret")
    }

    func testPrepareSecureStoreAccessReloadsVaultAfterNonInteractiveMiss() throws {
        let defaults = makeDefaults()
        let snapshot = [
            "\(KeychainService.defaultServiceName)::open.ailinyu.de/session-cookie": "cookie-value"
        ]
        let encodedSnapshot = try JSONEncoder().encode(snapshot)
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                guard service == KeychainService.defaultServiceName,
                      account == "__credential_vault__",
                      interactive else {
                    return nil
                }
                return encodedSnapshot
            },
            readAll: { _, _ in nil },
            saveData: { _, _, _, _ in true },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )

        let store = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )

        XCTAssertNil(
            store.readToken(
                service: KeychainService.defaultServiceName,
                account: "open.ailinyu.de/session-cookie"
            )
        )

        XCTAssertTrue(store.prepareSecureStoreAccess())
        XCTAssertEqual(
            store.readToken(
                service: KeychainService.defaultServiceName,
                account: "open.ailinyu.de/session-cookie"
            ),
            "cookie-value"
        )
    }

    func testIsSecureStoreReadyRecoversReadableVaultWithoutPreparedDefaults() throws {
        let defaults = makeDefaults()
        let snapshot = [
            "\(KeychainService.defaultServiceName)::open.ailinyu.de/sk-token": "sk-test-value"
        ]
        let encodedSnapshot = try JSONEncoder().encode(snapshot)
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, _ in
                guard service == KeychainService.defaultServiceName,
                      account == "__credential_vault__" else {
                    return nil
                }
                return encodedSnapshot
            },
            readAll: { _, _ in nil },
            saveData: { _, _, _, _ in true },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )

        let store = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )

        XCTAssertFalse(defaults.bool(forKey: "AIPlanMonitor.Keychain.SecureAccessPrepared"))
        XCTAssertTrue(store.isSecureStoreReady())
        XCTAssertTrue(defaults.bool(forKey: "AIPlanMonitor.Keychain.SecureAccessPrepared"))
        XCTAssertEqual(
            store.readToken(
                service: KeychainService.defaultServiceName,
                account: "open.ailinyu.de/sk-token"
            ),
            "sk-test-value"
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "KeychainServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
