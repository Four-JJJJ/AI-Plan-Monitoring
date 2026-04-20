import XCTest
@testable import AIPlanMonitor

final class AppConfigTests: XCTestCase {
    func testDecodeOldConfigDefaultsToChineseLanguage() throws {
        let json = #"{"providers":[]}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.language, .zhHans)
        XCTAssertNil(config.statusBarProviderID)
        XCTAssertFalse(config.statusBarMultiUsageEnabled)
        XCTAssertTrue(config.statusBarMultiProviderIDs.isEmpty)
        XCTAssertEqual(config.statusBarDisplayStyle, .iconPercent)
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

    func testDecodeOfficialConfigDefaultsPlanTypeDisplayEnabled() throws {
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
              "baseURL":"https://chatgpt.com",
              "officialConfig":{
                "sourceMode":"auto",
                "webMode":"autoImport",
                "manualCookieAccount":"official/codex/cookie-header",
                "autoDiscoveryEnabled":true,
                "quotaDisplayMode":"remaining"
              }
            }
          ]
        }
        """#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.providers.first?.officialConfig?.showPlanTypeInMenuBar, true)
    }

    func testDecodeOfficialConfigPlanTypeDisplayWhenPresent() throws {
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
              "baseURL":"https://chatgpt.com",
              "officialConfig":{
                "sourceMode":"auto",
                "webMode":"autoImport",
                "manualCookieAccount":"official/codex/cookie-header",
                "autoDiscoveryEnabled":true,
                "quotaDisplayMode":"remaining",
                "showPlanTypeInMenuBar":false
              }
            }
          ]
        }
        """#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.providers.first?.officialConfig?.showPlanTypeInMenuBar, false)
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
        XCTAssertEqual(config.statusBarMultiProviderIDs, ["codex-official"])
        XCTAssertFalse(config.statusBarMultiUsageEnabled)
        XCTAssertEqual(config.statusBarDisplayStyle, .iconPercent)
    }

    func testDecodeFiltersInvalidStatusBarMultiProviderIDs() throws {
        let json = #"""
        {
          "language":"zh-Hans",
          "statusBarProviderID":"codex-official",
          "statusBarMultiUsageEnabled":true,
          "statusBarMultiProviderIDs":["codex-official","ghost","codex-official","claude-official"],
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
            },
            {
              "id":"claude-official",
              "name":"Official Claude",
              "family":"official",
              "type":"claude",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"localCodex"},
              "baseURL":"https://claude.ai"
            }
          ]
        }
        """#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertTrue(config.statusBarMultiUsageEnabled)
        XCTAssertEqual(config.statusBarMultiProviderIDs, ["codex-official", "claude-official"])
        XCTAssertEqual(config.statusBarDisplayStyle, .iconPercent)
    }

    func testDecodeStatusBarDisplayStyleWhenPresent() throws {
        let json = #"""
        {
          "language":"zh-Hans",
          "statusBarDisplayStyle":"barNamePercent",
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
        XCTAssertEqual(config.statusBarDisplayStyle, .barNamePercent)
    }

    func testMigrationPromotesLegacyDefaultPollIntervalForCodexAndClaude() {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.pollIntervalSec = 60
        var claude = ProviderDescriptor.defaultOfficialClaude()
        claude.pollIntervalSec = 60

        let config = AppConfig(language: .zhHans, providers: [codex, claude])
        let migrated = config.migratedWithSiteDefaults()

        XCTAssertEqual(
            migrated.providers.first(where: { $0.id == "codex-official" })?.pollIntervalSec,
            120
        )
        XCTAssertEqual(
            migrated.providers.first(where: { $0.id == "claude-official" })?.pollIntervalSec,
            120
        )
    }

    func testMigrationDoesNotRewriteCustomOrNonTargetPollIntervals() {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.pollIntervalSec = 90
        var claude = ProviderDescriptor.defaultOfficialClaude()
        claude.pollIntervalSec = 180
        var gemini = ProviderDescriptor.defaultOfficialGemini()
        gemini.pollIntervalSec = 60

        let config = AppConfig(language: .zhHans, providers: [codex, claude, gemini])
        let migrated = config.migratedWithSiteDefaults()

        XCTAssertEqual(
            migrated.providers.first(where: { $0.id == "codex-official" })?.pollIntervalSec,
            90
        )
        XCTAssertEqual(
            migrated.providers.first(where: { $0.id == "claude-official" })?.pollIntervalSec,
            180
        )
        XCTAssertEqual(
            migrated.providers.first(where: { $0.id == "gemini-official" })?.pollIntervalSec,
            60
        )
    }
}
