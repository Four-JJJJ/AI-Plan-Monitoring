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
}
