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
        XCTAssertEqual(config.statusBarAppearanceMode, .followWallpaper)
        XCTAssertEqual(config.statusBarDisplayStyle, .iconPercent)
    }

    func testDecodeSkipsInvalidProviderEntriesInsteadOfFailingWholeConfig() throws {
        let json = #"""
        {
          "language":"zh-Hans",
          "providers":[
            {
              "id":"legacy-opencode-go",
              "name":"Legacy OpenCode Go",
              "family":"official",
              "type":"openCodeGo",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"bearer"}
            },
            {
              "id":"codex-official",
              "name":"Official Codex",
              "family":"official",
              "type":"codex",
              "enabled":true,
              "pollIntervalSec":180,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"localCodex"},
              "baseURL":"https://chatgpt.com"
            }
          ]
        }
        """#

        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.providers.count, 1)
        XCTAssertEqual(config.providers.first?.id, "codex-official")
        XCTAssertEqual(config.providers.first?.pollIntervalSec, 180)
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

    func testDefaultProvidersIncludeNewOfficialSourcesWithStableOrder() {
        let ids = AppConfig.default.providers.map(\.id)
        XCTAssertEqual(
            ids.suffix(5),
            [
                "kimi-official",
                "trae-official",
                "openrouter-credits-official",
                "openrouter-api-official",
                "ollama-cloud-official"
            ]
        )

        let trae = AppConfig.default.providers.first(where: { $0.id == "trae-official" })
        XCTAssertEqual(trae?.family, .official)
        XCTAssertEqual(trae?.type, .trae)
        XCTAssertEqual(trae?.auth.kind, .bearer)
        XCTAssertEqual(trae?.baseURL, "https://api-sg-central.trae.ai")

        let openRouterCredits = AppConfig.default.providers.first(where: { $0.id == "openrouter-credits-official" })
        XCTAssertEqual(openRouterCredits?.family, .official)
        XCTAssertEqual(openRouterCredits?.type, .openrouterCredits)
        XCTAssertEqual(openRouterCredits?.auth.kind, .bearer)
        XCTAssertEqual(openRouterCredits?.officialConfig?.sourceMode, .auto)
        XCTAssertEqual(openRouterCredits?.officialConfig?.webMode, .disabled)

        let openRouterAPI = AppConfig.default.providers.first(where: { $0.id == "openrouter-api-official" })
        XCTAssertEqual(openRouterAPI?.family, .official)
        XCTAssertEqual(openRouterAPI?.type, .openrouterAPI)
        XCTAssertEqual(openRouterAPI?.auth.kind, .bearer)
        XCTAssertEqual(openRouterAPI?.officialConfig?.sourceMode, .auto)
        XCTAssertEqual(openRouterAPI?.officialConfig?.webMode, .disabled)

        let ollama = AppConfig.default.providers.first(where: { $0.id == "ollama-cloud-official" })
        XCTAssertEqual(ollama?.family, .official)
        XCTAssertEqual(ollama?.type, .ollamaCloud)
        XCTAssertEqual(ollama?.auth.kind, AuthKind.none)
        XCTAssertEqual(ollama?.officialConfig?.sourceMode, .auto)
        XCTAssertEqual(ollama?.officialConfig?.webMode, .autoImport)
    }

    func testDefaultProvidersIncludeMicrosoftCopilotOfficialDescriptor() {
        let microsoft = AppConfig.default.providers.first(where: { $0.id == "microsoft-copilot-official" })
        XCTAssertEqual(microsoft?.family, .official)
        XCTAssertEqual(microsoft?.type, .microsoftCopilot)
        XCTAssertEqual(microsoft?.baseURL, "https://graph.microsoft.com")
        XCTAssertEqual(microsoft?.officialConfig?.sourceMode, .auto)
        XCTAssertEqual(microsoft?.officialConfig?.webMode, .disabled)
    }

    func testDefaultOfficialClaudeUsesUsedQuotaDisplayMode() {
        XCTAssertEqual(
            ProviderDescriptor.defaultOfficialClaude().officialConfig?.quotaDisplayMode,
            .used
        )
    }

    func testDefaultOfficialTraeUsesPercentValueDisplayAndRemainingQuotaPreference() {
        let config = ProviderDescriptor.defaultOfficialConfig(type: .trae)
        XCTAssertEqual(config.traeValueDisplayMode, .percent)
        XCTAssertEqual(config.quotaDisplayMode, .remaining)
    }

    func testDecodeLegacyTraeQuotaDisplayModeMigratesToIndependentFields() throws {
        let json = #"""
        {
          "language":"zh-Hans",
          "providers":[
            {
              "id":"trae-official",
              "name":"Official Trae",
              "family":"official",
              "type":"trae",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"bearer"},
              "baseURL":"https://api-sg-central.trae.ai",
              "officialConfig":{
                "sourceMode":"auto",
                "webMode":"disabled",
                "autoDiscoveryEnabled":true,
                "quotaDisplayMode":"used"
              }
            }
          ]
        }
        """#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        let traeConfig = try XCTUnwrap(config.providers.first?.officialConfig)
        XCTAssertEqual(traeConfig.traeValueDisplayMode, .amount)
        XCTAssertEqual(traeConfig.quotaDisplayMode, .remaining)
    }

    func testThirdPartyDisplaysUsedQuotaFollowsRelayQuotaPreference() {
        var relayProvider = ProviderDescriptor.makeOpenRelay(
            name: "Relay Example",
            baseURL: "https://relay.example.com"
        )
        relayProvider.relayConfig?.quotaDisplayMode = .used
        relayProvider = relayProvider.normalized()
        XCTAssertTrue(relayProvider.displaysUsedQuota)

        relayProvider.relayConfig?.quotaDisplayMode = .remaining
        relayProvider = relayProvider.normalized()
        XCTAssertFalse(relayProvider.displaysUsedQuota)
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
        XCTAssertEqual(config.statusBarAppearanceMode, .followWallpaper)
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
        XCTAssertEqual(config.statusBarAppearanceMode, .followWallpaper)
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

    func testDecodeStatusBarAppearanceModeWhenPresent() throws {
        let json = #"""
        {
          "language":"zh-Hans",
          "statusBarAppearanceMode":"dark",
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
        XCTAssertEqual(config.statusBarAppearanceMode, .dark)
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
