import XCTest
@testable import AIPlanMonitor

final class BrowserCredentialServiceTests: XCTestCase {
    func testBearerCandidatesUsesShortLivedCacheForSameHost() {
        var lookupCount = 0
        let service = BrowserCredentialService(
            bearerCandidatesOverride: { host in
                lookupCount += 1
                return [BrowserDetectedCredential(value: "token-\(host)", source: "browser")]
            },
            cacheTTL: 30
        )

        let first = service.detectBearerTokenCandidates(host: "Platform.DeepSeek.com")
        let second = service.detectBearerTokenCandidates(host: "platform.deepseek.com")

        XCTAssertEqual(first, second)
        XCTAssertEqual(lookupCount, 1)
    }

    func testCookieHeaderCachesNegativeLookupResults() {
        var lookupCount = 0
        let service = BrowserCredentialService(
            cookieHeaderOverride: { _ in
                lookupCount += 1
                return nil
            },
            cacheTTL: 30
        )

        XCTAssertNil(service.detectCookieHeader(host: "relay.example.com"))
        let firstPassCount = lookupCount
        XCTAssertGreaterThan(firstPassCount, 0)

        XCTAssertNil(service.detectCookieHeader(host: "relay.example.com"))
        XCTAssertEqual(lookupCount, firstPassCount)
    }

    func testNamedCookieCachesNegativeLookupResults() {
        var lookupCount = 0
        let service = BrowserCredentialService(
            namedCookieOverride: { _, _ in
                lookupCount += 1
                return nil
            },
            cacheTTL: 30
        )

        XCTAssertNil(service.detectNamedCookie(name: "sessionKey", host: "claude.ai"))
        let firstPassCount = lookupCount
        XCTAssertGreaterThan(firstPassCount, 0)

        XCTAssertNil(service.detectNamedCookie(name: "sessionKey", host: "claude.ai"))
        XCTAssertEqual(lookupCount, firstPassCount)
    }

    func testBackgroundIntentSkipsBearerLookupWhenCacheEmpty() {
        var lookupCount = 0
        let service = BrowserCredentialService(
            bearerCandidatesOverride: { _ in
                lookupCount += 1
                return [BrowserDetectedCredential(value: "token", source: "browser")]
            },
            cacheTTL: 30
        )

        let candidates = service.detectBearerTokenCandidates(
            host: "platform.deepseek.com",
            accessIntent: .background
        )

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertEqual(lookupCount, 0)
    }

    func testBackgroundIntentCanReuseCachedCookieHeader() {
        var lookupCount = 0
        let service = BrowserCredentialService(
            cookieHeaderOverride: { _ in
                lookupCount += 1
                return BrowserDetectedCredential(value: "session=ok", source: "browser")
            },
            cacheTTL: 30
        )

        XCTAssertEqual(
            service.detectCookieHeader(host: "relay.example.com")?.value,
            "session=ok"
        )
        XCTAssertEqual(lookupCount, 1)

        XCTAssertEqual(
            service.detectCookieHeader(
                host: "relay.example.com",
                accessIntent: .background
            )?.value,
            "session=ok"
        )
        XCTAssertEqual(lookupCount, 1)
    }
}
