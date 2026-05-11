import XCTest
@testable import OhMyUsage

final class AppConfigRelayCompatibilityTests: XCTestCase {
    func testDecodedLegacySimplifiedRelayConfigFalseNormalizesToCurrentBehavior() throws {
        let json = """
        {
          "language": "zh-Hans",
          "launchAtLoginEnabled": false,
          "simplifiedRelayConfig": false,
          "providers": []
        }
        """

        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))

        XCTAssertTrue(config.simplifiedRelayConfig)
    }

    func testInitializerIgnoresLegacySimplifiedRelayConfigFalse() {
        let config = AppConfig(simplifiedRelayConfig: false, providers: [])

        XCTAssertTrue(config.simplifiedRelayConfig)
    }
}
