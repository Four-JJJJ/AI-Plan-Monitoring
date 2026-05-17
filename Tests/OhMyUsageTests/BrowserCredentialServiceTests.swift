import XCTest
@testable import OhMyUsage

final class BrowserCredentialServiceTests: XCTestCase {
    func testBrowserCookieDatabaseReaderReadsNamedCookieFromPlainCookiesSchema() throws {
        let databasePath = try makeCookieDatabase(
            sql: """
            CREATE TABLE cookies (name TEXT, value TEXT, host TEXT);
            INSERT INTO cookies VALUES ('sessionKey', 'plain-token', '.claude.ai');
            INSERT INTO cookies VALUES ('other', 'ignored', '.example.com');
            """
        )
        defer { try? FileManager.default.removeItem(atPath: databasePath) }

        let reader = BrowserCookieDatabaseReader()
        let value = reader.namedCookieValue(
            fromDatabaseAt: databasePath,
            browser: .firefox,
            cookieName: "sessionKey",
            hostContains: "claude.ai"
        )

        XCTAssertEqual(value, "plain-token")
    }

    func testBrowserCookieDatabaseReaderBuildsCookieHeaderFromPlainCookiesSchema() throws {
        let databasePath = try makeCookieDatabase(
            sql: """
            CREATE TABLE cookies (name TEXT, value TEXT, host TEXT);
            INSERT INTO cookies VALUES ('a', '1', '.kimi.com');
            INSERT INTO cookies VALUES ('b', '2', '.www.kimi.com');
            INSERT INTO cookies VALUES ('ignored', 'x', '.example.com');
            """
        )
        defer { try? FileManager.default.removeItem(atPath: databasePath) }

        let reader = BrowserCookieDatabaseReader()
        let header = reader.cookieHeader(
            fromDatabaseAt: databasePath,
            browser: .firefox,
            hostContains: "kimi.com"
        )

        XCTAssertEqual(header, "a=1; b=2")
    }

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

    func testBrowserStorageCredentialReaderFindsBearerCandidatesInHostStorage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("leveldb", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        let token = "sk-\(String(repeating: "a", count: 32))"
        let text = "_https://hongmacc.com auth_token Bearer \(token)"
        try text.write(
            to: directory.appendingPathComponent("000003.log"),
            atomically: true,
            encoding: .isoLatin1
        )

        let reader = BrowserStorageCredentialReader()
        let candidates = reader.bearerTokenCandidates(
            storagePaths: [directory.path],
            host: "hongmacc.com",
            source: "test:localStorage"
        )

        XCTAssertEqual(candidates, [BrowserDetectedCredential(value: token, source: "test:localStorage")])
    }

    private func makeCookieDatabase(sql: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("cookies.sqlite").path
        guard let result = ShellCommand.run(executable: "/usr/bin/sqlite3", arguments: [path, sql], timeout: 5) else {
            throw NSError(domain: "BrowserCredentialServiceTests", code: 1)
        }
        XCTAssertEqual(result.status, 0, result.stderr)
        return path
    }
}
