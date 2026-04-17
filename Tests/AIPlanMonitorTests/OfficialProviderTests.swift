import Foundation
import XCTest
@testable import AIPlanMonitor

final class OfficialProviderTests: XCTestCase {
    func testConfigMigrationInjectsOfficialProviders() {
        let legacy = AppConfig(language: .zhHans, providers: [])
        let migrated = legacy.migratedWithSiteDefaults()

        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "codex-official" && $0.family == .official }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "claude-official" && $0.family == .official }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "gemini-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "copilot-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "zai-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "amp-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "cursor-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "jetbrains-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "kiro-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "windsurf-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "kimi-official" && $0.family == .official && !$0.enabled }))
    }

    func testLegacyCodexDescriptorNormalizesToOfficialFamily() {
        let legacy = ProviderDescriptor(
            id: "codex-official",
            name: "Official Codex",
            type: .codex,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .localCodex)
        )

        let normalized = legacy.normalized()
        XCTAssertEqual(normalized.family, .official)
        XCTAssertEqual(normalized.officialConfig?.sourceMode, .auto)
        XCTAssertEqual(normalized.officialConfig?.webMode, .autoImport)
    }

    func testCodexAPIResponseParsesQuotaWindows() throws {
        let json = """
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": { "used_percent": 25, "reset_at": 1760000000, "limit_window_seconds": 18000 },
            "secondary_window": { "used_percent": 60, "reset_at": 1760500000, "limit_window_seconds": 604800 }
          },
          "code_review_rate_limit": {
            "primary_window": { "used_percent": 10, "reset_at": 1760600000, "limit_window_seconds": 604800 }
          },
          "credits": { "balance": 42.5 }
        }
        """

        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["x-codex-primary-used-percent": "25", "x-codex-secondary-used-percent": "60"]
        )!

        let snapshot = try CodexProvider.parseUsageSnapshot(
            data: Data(json.utf8),
            response: response,
            descriptor: ProviderDescriptor.defaultOfficialCodex(),
            sourceLabel: "API",
            accountLabel: "test@example.com"
        )

        XCTAssertEqual(snapshot.sourceLabel, "API")
        XCTAssertEqual(snapshot.accountLabel, "test@example.com")
        XCTAssertEqual(snapshot.quotaWindows.count, 3)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .session })?.remainingPercent ?? -1, 75, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.remainingPercent ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["creditsBalance"], "42.50")
    }

    func testCodexForceRefreshDoesNotReturnStaleCachedSnapshot() async throws {
        let homeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-provider-tests-\(UUID().uuidString)", isDirectory: true)
        let authDirectory = homeDirectory.appendingPathComponent(".config/codex", isDirectory: true)
        try FileManager.default.createDirectory(at: authDirectory, withIntermediateDirectories: true)

        let idTokenPayload = Data(#"{"email":"codex@example.com"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let authJSON = #"""
        {
          "last_refresh": "\#(ISO8601DateFormatter().string(from: Date()))",
          "tokens": {
            "access_token": "codex-access-token",
            "refresh_token": "codex-refresh-token",
            "account_id": "codex-account",
            "id_token": "header.\#(idTokenPayload).signature"
          }
        }
        """#
        try authJSON.write(to: authDirectory.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let originalHome = ProcessInfo.processInfo.environment["HOME"]
        setenv("HOME", homeDirectory.path, 1)
        defer {
            if let originalHome {
                setenv("HOME", originalHome, 1)
            } else {
                unsetenv("HOME")
            }
        }

        var requestCount = 0
        OfficialMockURLProtocol.requestHandler = { request in
            requestCount += 1
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
            if requestCount == 1 {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {
                  "plan_type": "plus",
                  "rate_limit": {
                    "primary_window": { "used_percent": 25, "reset_at": 1760000000 },
                    "secondary_window": { "used_percent": 60, "reset_at": 1760500000 }
                  }
                }
                """
                return (response, Data(body.utf8))
            }
            let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        var descriptor = ProviderDescriptor.defaultOfficialCodex()
        descriptor.officialConfig?.sourceMode = .api
        descriptor.officialConfig?.webMode = .disabled

        let provider = CodexProvider(
            descriptor: descriptor,
            session: session,
            keychain: KeychainService(),
            browserCookieService: BrowserCookieService()
        )

        let initial = try await provider.fetch(forceRefresh: false)
        XCTAssertEqual(initial.remaining ?? -1, 40, accuracy: 0.001)

        do {
            _ = try await provider.fetch(forceRefresh: true)
            XCTFail("forceRefresh should not fall back to a stale cached snapshot")
        } catch let error as ProviderError {
            if case .unauthorized = error {
                XCTAssertEqual(requestCount, 2)
            } else {
                XCTFail("unexpected provider error: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testCodexWebWithManualCookieSkipsBrowserDetection() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "manual-cookie=ok")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "plan_type": "plus",
              "rate_limit": {
                "primary_window": { "used_percent": 20, "reset_at": 1760000000 },
                "secondary_window": { "used_percent": 40, "reset_at": 1760500000 }
              }
            }
            """
            return (response, Data(body.utf8))
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let keychain = KeychainService()
        let account = "official/codex/cookie-header-\(UUID().uuidString)"
        XCTAssertTrue(keychain.saveToken("manual-cookie=ok", service: KeychainService.defaultServiceName, account: account))

        var descriptor = ProviderDescriptor.defaultOfficialCodex()
        descriptor.id = "codex-web-manual-\(UUID().uuidString)"
        descriptor.officialConfig?.sourceMode = .web
        descriptor.officialConfig?.webMode = .autoImport
        descriptor.officialConfig?.manualCookieAccount = account

        let spy = SpyBrowserCookieDetector()
        let provider = CodexProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCookieService: spy,
            webReadBackoff: WebOverlayRetryBackoff()
        )

        let snapshot = try await provider.fetch(forceRefresh: true)
        XCTAssertEqual(snapshot.sourceLabel, "Web")
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 0)
    }

    func testCodexWebBackoffSkipsRepeatedBrowserReadAndForceRefreshBypasses() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        OfficialMockURLProtocol.requestHandler = { request in
            XCTFail("browser cookie missing should fail before network request, got \(request.url?.absoluteString ?? "nil")")
            let response = HTTPURLResponse(url: request.url ?? URL(string: "https://chatgpt.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        var descriptor = ProviderDescriptor.defaultOfficialCodex()
        descriptor.id = "codex-web-backoff-\(UUID().uuidString)"
        descriptor.officialConfig?.sourceMode = .web
        descriptor.officialConfig?.webMode = .autoImport
        descriptor.officialConfig?.manualCookieAccount = "official/codex/cookie-header-\(UUID().uuidString)"

        let spy = SpyBrowserCookieDetector()
        let provider = CodexProvider(
            descriptor: descriptor,
            session: session,
            keychain: KeychainService(),
            browserCookieService: spy,
            webReadBackoff: WebOverlayRetryBackoff()
        )

        await XCTAssertThrowsProviderError {
            _ = try await provider.fetch(forceRefresh: false)
        }
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 1)

        await XCTAssertThrowsProviderError {
            _ = try await provider.fetch(forceRefresh: false)
        }
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 1)

        await XCTAssertThrowsProviderError {
            _ = try await provider.fetch(forceRefresh: true)
        }
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 2)
    }

    func testClaudeWebBackoffSkipsRepeatedBrowserRead() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        OfficialMockURLProtocol.requestHandler = { request in
            XCTFail("browser cookie missing should fail before network request, got \(request.url?.absoluteString ?? "nil")")
            let response = HTTPURLResponse(url: request.url ?? URL(string: "https://claude.ai")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        var descriptor = ProviderDescriptor.defaultOfficialClaude()
        descriptor.id = "claude-web-backoff-\(UUID().uuidString)"
        descriptor.officialConfig?.sourceMode = .web
        descriptor.officialConfig?.webMode = .autoImport
        descriptor.officialConfig?.manualCookieAccount = "official/claude/cookie-header-\(UUID().uuidString)"

        let spy = SpyBrowserCookieDetector()
        let provider = ClaudeProvider(
            descriptor: descriptor,
            session: session,
            keychain: KeychainService(),
            browserCookieService: spy,
            webReadBackoff: WebOverlayRetryBackoff()
        )

        await XCTAssertThrowsProviderError {
            _ = try await provider.fetch(forceRefresh: false)
        }
        XCTAssertEqual(spy.detectNamedCookieCallCount, 1)
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 1)

        await XCTAssertThrowsProviderError {
            _ = try await provider.fetch(forceRefresh: false)
        }
        XCTAssertEqual(spy.detectNamedCookieCallCount, 1)
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 1)
    }

    func testClaudeOAuthResponseParsesWindowsAndExtraUsage() throws {
        let root: [String: Any] = [
            "five_hour": ["utilization": 30, "resets_at": "2026-04-11T10:00:00Z"],
            "seven_day": ["utilization": 55, "resets_at": "2026-04-17T00:00:00Z"],
            "seven_day_opus": ["utilization": 80, "resets_at": "2026-04-17T00:00:00Z"],
            "extra_usage": ["used_credits": 1200, "monthly_limit": 5000]
        ]

        let snapshot = try ClaudeProvider.parseClaudeSnapshot(
            root: root,
            descriptor: ProviderDescriptor.defaultOfficialClaude(),
            sourceLabel: "API",
            accountLabel: "claude@example.com",
            planHint: "pro"
        )

        XCTAssertEqual(snapshot.sourceLabel, "API")
        XCTAssertEqual(snapshot.accountLabel, "claude@example.com")
        XCTAssertEqual(snapshot.quotaWindows.count, 3)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .session })?.remainingPercent ?? -1, 70, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.remainingPercent ?? -1, 45, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["extraUsageCost"], "1200.00")
        XCTAssertEqual(snapshot.extras["extraUsageLimit"], "5000.00")
    }

    func testClaudeOAuthResponseWithoutPlanAndWithAllZeroUsageIsRejected() throws {
        let root: [String: Any] = [
            "five_hour": ["utilization": 0],
            "seven_day": ["utilization": 0]
        ]

        XCTAssertThrowsError(
            try ClaudeProvider.parseClaudeSnapshot(
                root: root,
                descriptor: ProviderDescriptor.defaultOfficialClaude(),
                sourceLabel: "API",
                accountLabel: nil,
                planHint: nil
            )
        ) { error in
            guard case let ProviderError.unavailable(message) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("subscription"))
        }
    }

    func testGeminiQuotaResponseParsesProAndFlashWindows() throws {
        let quotaRoot: [String: Any] = [
            "quotaInfos": [
                [
                    "quotaId": "gemini-2.5-pro",
                    "usage": ["utilization": 0.40, "resetAt": "2026-04-11T08:00:00Z"],
                ],
                [
                    "quotaId": "gemini-2.5-flash",
                    "usage": ["utilization": 20, "resetAt": "2026-04-11T02:00:00Z"],
                ],
            ]
        ]
        let codeAssistRoot: [String: Any] = ["tierId": "legacy-pro"]

        let snapshot = try GeminiProvider.parseQuotaSnapshot(
            root: quotaRoot,
            codeAssistRoot: codeAssistRoot,
            descriptor: ProviderDescriptor.defaultOfficialGemini(),
            sourceLabel: "API",
            accountLabel: "gemini@example.com",
            projectLabel: "demo-project"
        )

        XCTAssertEqual(snapshot.sourceLabel, "API")
        XCTAssertEqual(snapshot.accountLabel, "gemini@example.com")
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Pro" })?.remainingPercent ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Flash" })?.remainingPercent ?? -1, 80, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "pro")
        XCTAssertEqual(snapshot.extras["project"], "demo-project")
    }

    func testGeminiQuotaResponseParsesBucketsShapeFromGeminiCLI() throws {
        let quotaRoot: [String: Any] = [
            "buckets": [
                [
                    "modelId": "gemini-2.5-pro",
                    "remainingAmount": "400",
                    "remainingFraction": 0.40,
                    "resetTime": "2026-04-11T08:00:00Z",
                ],
                [
                    "modelId": "gemini-2.5-flash",
                    "remainingAmount": "900",
                    "remainingFraction": 0.90,
                    "resetTime": "2026-04-11T02:00:00Z",
                ],
            ]
        ]
        let codeAssistRoot: [String: Any] = [
            "currentTier": ["id": "legacy-pro"],
            "cloudaicompanionProject": "demo-project",
        ]

        let snapshot = try GeminiProvider.parseQuotaSnapshot(
            root: quotaRoot,
            codeAssistRoot: codeAssistRoot,
            descriptor: ProviderDescriptor.defaultOfficialGemini(),
            sourceLabel: "API",
            accountLabel: "gemini@example.com",
            projectLabel: "demo-project"
        )

        XCTAssertEqual(snapshot.sourceLabel, "API")
        XCTAssertEqual(snapshot.accountLabel, "gemini@example.com")
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Pro" })?.remainingPercent ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Flash" })?.remainingPercent ?? -1, 90, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "pro")
        XCTAssertEqual(snapshot.extras["project"], "demo-project")
    }

    func testGeminiClientSecretParserSupportsNewBundleConstants() {
        let source = #"""
        var OAUTH_CLIENT_ID = "demo-client.apps.googleusercontent.com";
        var OAUTH_CLIENT_SECRET = "demo-secret";
        """#

        let parsed = GeminiProvider.parseClientSecrets(in: source)
        XCTAssertEqual(parsed?.id, "demo-client.apps.googleusercontent.com")
        XCTAssertEqual(parsed?.secret, "demo-secret")
    }

    func testGeminiClientSecretParserSupportsLegacyOAuthFilePattern() {
        let source = #"""
        export const oauthConfig = {
          client_id: "legacy-client.apps.googleusercontent.com",
          client_secret: "legacy-secret"
        };
        """#

        let parsed = GeminiProvider.parseClientSecrets(in: source)
        XCTAssertEqual(parsed?.id, "legacy-client.apps.googleusercontent.com")
        XCTAssertEqual(parsed?.secret, "legacy-secret")
    }

    func testOfficialKimiResponseParsesSessionAndOverallUsage() throws {
        let root: [String: Any] = [
            "user": [
                "email": "kimi@example.com",
                "membership": ["level": "premium"],
            ],
            "usage": [
                "remaining_amount": 700,
                "quota_amount": 1000,
            ],
            "limits": [
                [
                    "name": "5-hour",
                    "window": ["duration": 300, "time_unit": "TIME_UNIT_MINUTE", "resets_at": "2026-04-10T12:00:00Z"],
                    "usage": ["remaining_amount": 30, "quota_amount": 50],
                ]
            ],
        ]

        let snapshot = try KimiOfficialProvider.parseUsageSnapshot(
            root: root,
            descriptor: ProviderDescriptor.defaultOfficialKimi(),
            sourceLabel: "API"
        )

        XCTAssertEqual(snapshot.sourceLabel, "API")
        XCTAssertEqual(snapshot.accountLabel, "kimi@example.com")
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .session })?.remainingPercent ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Overall" })?.remainingPercent ?? -1, 70, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "premium")
    }

    func testOfficialKimiResponseParsesResetTimeFromCamelCaseAndEpochMillis() throws {
        let root: [String: Any] = [
            "user": [
                "email": "kimi@example.com",
                "membership": ["level": "premium"],
            ],
            "usage": [
                "remaining_amount": 620,
                "quota_amount": 1000,
                "nextCycleAt": 1_776_000_000_000 as Double,
            ],
            "limits": [
                [
                    "name": "5-hour",
                    "window": ["duration": 300, "timeUnit": "TIME_UNIT_MINUTE"],
                    "usage": [
                        "remaining_amount": 35,
                        "quota_amount": 50,
                        "resetTime": "2026-04-11T12:30:00Z",
                    ],
                ]
            ],
        ]

        let snapshot = try KimiOfficialProvider.parseUsageSnapshot(
            root: root,
            descriptor: ProviderDescriptor.defaultOfficialKimi(),
            sourceLabel: "API"
        )

        XCTAssertNotNil(snapshot.quotaWindows.first(where: { $0.kind == .session })?.resetAt)
        XCTAssertNotNil(snapshot.quotaWindows.first(where: { $0.title == "Overall" })?.resetAt)
    }

    func testCopilotResponseParsesPremiumAndChat() throws {
        let json = """
        {
          "copilot_plan": "pro",
          "quota_reset_date": "2026-04-30T00:00:00Z",
          "quota_snapshots": {
            "premium_interactions": { "percent_remaining": 80, "entitlement": 300, "remaining": 240 },
            "chat": { "percent_remaining": 95, "entitlement": 1000, "remaining": 950 }
          }
        }
        """

        let snapshot = try CopilotProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: ProviderDescriptor.defaultOfficialCopilot()
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Premium" })?.remainingPercent ?? -1, 80, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "pro")
    }

    func testZaiResponseParsesSessionWeeklyAndWeb() throws {
        let subscriptionRoot: [String: Any] = [
            "data": [[
                "productName": "GLM Coding Max",
                "inCurrentPeriod": true,
                "nextRenewTime": "2026-05-12",
            ]]
        ]
        let quotaRoot: [String: Any] = [
            "data": [
                "limits": [
                    ["type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 15, "nextResetTime": 1770648402389 as Double],
                    ["type": "TOKENS_LIMIT", "unit": 6, "number": 7, "percentage": 45, "nextResetTime": 1771200000000 as Double],
                    ["type": "TIME_LIMIT", "remaining": 2172, "usage": 4000],
                ]
            ]
        ]

        let snapshot = try ZaiProvider.parseSnapshot(
            subscriptionRoot: subscriptionRoot,
            quotaRoot: quotaRoot,
            descriptor: ProviderDescriptor.defaultOfficialZai()
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 3)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .session })?.remainingPercent ?? -1, 85, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "GLM Coding Max")
    }

    func testAmpResponseParsesFreeAndCredits() throws {
        let json = """
        {
          "ok": true,
          "result": {
            "displayText": "Signed in as test\\nAmp Free: $12.50/$20.00 remaining (replenishes +$1.50/hour)\\nIndividual credits: $8.25 remaining"
          }
        }
        """

        let snapshot = try AmpProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: ProviderDescriptor.defaultOfficialAmp()
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Free" })?.remainingPercent ?? -1, 62.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["creditsBalance"], "8.25")
    }

    func testCursorResponseParsesMonthlyAndOnDemand() throws {
        let json = """
        {
          "membershipType": "ultra",
          "billingCycleEnd": "2026-05-01T00:00:00Z",
          "individualUsage": {
            "plan": { "enabled": true, "used": 326, "limit": 40000, "remaining": 39674 },
            "onDemand": { "enabled": true, "used": 10, "limit": 100, "remaining": 90 }
          }
        }
        """

        let snapshot = try CursorProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: ProviderDescriptor.defaultOfficialCursor(),
            accountLabel: "cursor@example.com"
        )

        XCTAssertEqual(snapshot.accountLabel, "cursor@example.com")
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.extras["planType"], "ultra")
    }

    func testJetBrainsXMLParsesQuota() throws {
        let xml = """
        <application>
          <component name="AIAssistantQuotaManager2">
            <option name="nextRefill" value="{&quot;type&quot;:&quot;Known&quot;,&quot;next&quot;:&quot;2099-01-01T00:00:00Z&quot;,&quot;tariff&quot;:{&quot;amount&quot;:&quot;100&quot;,&quot;duration&quot;:&quot;PT720H&quot;}}" />
            <option name="quotaInfo" value="{&quot;type&quot;:&quot;Available&quot;,&quot;current&quot;:&quot;75&quot;,&quot;maximum&quot;:&quot;100&quot;,&quot;available&quot;:&quot;25&quot;,&quot;until&quot;:&quot;2099-01-31T00:00:00Z&quot;}" />
          </component>
        </application>
        """

        let snapshot = try JetBrainsProvider.parseSnapshot(
            xml: xml,
            descriptor: ProviderDescriptor.defaultOfficialJetBrains()
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        XCTAssertEqual(snapshot.quotaWindows.first?.remainingPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(snapshot.sourceLabel, "Local")
    }

    func testKiroCLIOutputParsesCreditsAndBonus() throws {
        let text = """
        Estimated Usage | resets on 03/01 | KIRO FREE

        Bonus credits: 122.54/500 credits used, expires in 29 days

        Credits (0.00 of 50 covered in plan)
        """

        let snapshot = try KiroProvider.parseSnapshot(
            text: text,
            descriptor: ProviderDescriptor.defaultOfficialKiro()
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.sourceLabel, "CLI")
    }

    func testWindsurfResponseParsesDailyAndWeekly() throws {
        let json = """
        {
          "userStatus": {
            "planStatus": {
              "planInfo": { "planName": "Pro" },
              "dailyQuotaRemainingPercent": 72,
              "weeklyQuotaRemainingPercent": 55,
              "dailyQuotaResetAtUnix": 1770648402,
              "weeklyQuotaResetAtUnix": 1771200000,
              "overageBalanceMicros": 2500000
            }
          }
        }
        """

        let snapshot = try WindsurfProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: ProviderDescriptor.defaultOfficialWindsurf()
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 3)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .session })?.remainingPercent ?? -1, 72, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "Pro")
    }
}

private final class OfficialMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = OfficialMockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func XCTAssertThrowsProviderError(
    _ operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await operation()
        XCTFail("Expected ProviderError", file: file, line: line)
    } catch is ProviderError {
        return
    } catch {
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}

private final class SpyBrowserCookieDetector: BrowserCookieDetecting {
    var detectCookieHeaderCallCount = 0
    var detectNamedCookieCallCount = 0
    var cookieHeaderResult: BrowserCookieHeader?
    var namedCookieResult: BrowserCookieHeader?

    func detectCookieHeader(hostContains: String, order: [KimiBrowserKind]?) -> BrowserCookieHeader? {
        detectCookieHeaderCallCount += 1
        return cookieHeaderResult
    }

    func detectNamedCookie(name: String, hostContains: String, order: [KimiBrowserKind]?) -> BrowserCookieHeader? {
        detectNamedCookieCallCount += 1
        return namedCookieResult
    }
}
