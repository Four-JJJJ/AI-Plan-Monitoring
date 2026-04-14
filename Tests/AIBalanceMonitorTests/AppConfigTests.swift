import XCTest
@testable import AIBalanceMonitor

final class AppConfigTests: XCTestCase {
    func testDecodeOldConfigDefaultsToChineseLanguage() throws {
        let json = #"{"providers":[]}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.language, .zhHans)
        XCTAssertNil(config.statusBarProviderID)
    }

    func testNormalizeRelayBaseURLStripsPathAndQuery() {
        let normalized = ProviderDescriptor.normalizeRelayBaseURL("platform.deepseek.com/usage?month=4")
        XCTAssertEqual(normalized, "https://platform.deepseek.com")
    }

    func testDefaultStatusBarProviderIsNilWhenNothingIsEnabled() {
        let config = AppConfig.default
        XCTAssertNil(config.statusBarProviderID)
    }

    func testDefaultStatusBarProviderUsesEnabledOfficialCodex() {
        let providers = [
            ProviderDescriptor.defaultOfficialCodex(),
            ProviderDescriptor.defaultOfficialClaude()
        ].map {
            var copy = $0
            copy.enabled = copy.type == .codex
            return copy
        }

        XCTAssertEqual(AppConfig.defaultStatusBarProviderID(from: providers), "codex-official")
    }

    func testDefaultOfficialClaudeUsesUsedQuotaDisplayMode() {
        XCTAssertEqual(
            ProviderDescriptor.defaultOfficialClaude().officialConfig?.quotaDisplayMode,
            .used
        )
    }

    func testDecodeMissingStatusBarProviderFallsBackToDefault() throws {
        let json = #"""
        {
          "language":"zh-Hans",
          "providers":[
            {
              "id":"codex-official",
              "name":"Official Codex",
              "family":"official",
              "type":"codex",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"localCodex"},
              "baseURL":"https://chatgpt.com"
            }
          ]
        }
        """#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.statusBarProviderID, "codex-official")
    }
}
