import Foundation
import XCTest
@testable import AIBalanceMonitor

final class KimiProviderTests: XCTestCase {
    func testParseSnapshotWithWeeklyAndFiveHourLimits() throws {
        let json = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": { "limit": "1000", "used": "400", "remaining": "600", "resetTime": "2026-04-12T12:00:00Z" },
              "limits": [
                {
                  "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                  "detail": { "limit": 100, "used": 20, "remaining": 80, "resetTime": "2026-04-10T15:00:00Z" }
                }
              ]
            }
          ]
        }
        """

        let snapshot = try KimiProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: makeDescriptor(threshold: 20),
            authSource: "manual",
            now: Date(timeIntervalSince1970: 1_710_000_000)
        )

        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.remaining ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(snapshot.used ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(snapshot.unit, "%")
        XCTAssertEqual(snapshot.rawMeta["kimi.authSource"], "manual")
        XCTAssertEqual(snapshot.rawMeta["kimi.weekly.remaining"], "600.00")
        XCTAssertEqual(snapshot.rawMeta["kimi.window5h.remaining"], "80.00")
        XCTAssertNotNil(snapshot.rawMeta["kimi.weekly.resetAt"])
        XCTAssertNotNil(snapshot.rawMeta["kimi.window5h.resetAt"])
    }

    func testParseSnapshotFallsBackToFirstLimitWhenNoFiveHourWindow() throws {
        let json = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": { "limit": 100, "used": 95, "remaining": 5 },
              "limits": [
                {
                  "window": { "duration": 60, "timeUnit": "TIME_UNIT_MINUTE" },
                  "detail": { "limit": 10, "used": 9, "remaining": 1 }
                }
              ]
            }
          ]
        }
        """

        let snapshot = try KimiProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: makeDescriptor(threshold: 15),
            authSource: "auto:Chrome"
        )

        XCTAssertEqual(snapshot.status, .warning)
        XCTAssertEqual(snapshot.remaining ?? -1, 5, accuracy: 0.001)
    }

    func testFetchReturnsUnauthorizedOn401() async throws {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages")!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        defer { MockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let provider = KimiProvider(
            descriptor: makeDescriptor(),
            session: session,
            keychain: KeychainService(),
            browserCookieService: KimiBrowserCookieService(),
            tokenResolverOverride: { ("fake.jwt.token", "manual") }
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected unauthorized error")
        } catch let error as ProviderError {
            if case .unauthorized = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchNormalizesBearerPrefixedTokenBeforeRequest() async throws {
        let pureToken = jwt(exp: Int(Date().timeIntervalSince1970) + 3600)
        let prefixed = "Bearer \(pureToken)"
        let json = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": { "limit": 100, "used": 20, "remaining": 80 },
              "limits": [
                {
                  "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                  "detail": { "limit": 10, "used": 1, "remaining": 9 }
                }
              ]
            }
          ]
        }
        """

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(pureToken)")
            let response = HTTPURLResponse(
                url: URL(string: "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let provider = KimiProvider(
            descriptor: makeDescriptor(),
            session: session,
            keychain: KeychainService(),
            browserCookieService: KimiBrowserCookieService(),
            tokenResolverOverride: { (prefixed, "manual") }
        )

        _ = try await provider.fetch()
    }

    func testManualTokenHasPriorityOverAutoToken() async throws {
        let service = "AIBalanceMonitorTests-\(UUID().uuidString)"
        let manualToken = jwt(exp: Int(Date().timeIntervalSince1970) + 3600)
        let autoToken = jwt(exp: Int(Date().timeIntervalSince1970) + 7200)
        let keychain = KeychainService()
        XCTAssertTrue(keychain.saveToken(manualToken, service: service, account: "kimi.com/kimi-auth-manual"))
        XCTAssertTrue(keychain.saveToken(autoToken, service: service, account: "kimi.com/kimi-auth-auto"))

        let json = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": { "limit": 100, "used": 20, "remaining": 80 },
              "limits": [
                {
                  "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                  "detail": { "limit": 10, "remaining": 9 }
                }
              ]
            }
          ]
        }
        """

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(manualToken)")
            let response = HTTPURLResponse(
                url: URL(string: "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        var descriptor = makeDescriptor(threshold: 10)
        descriptor.auth.keychainService = service
        descriptor.kimiConfig?.authMode = .auto

        let provider = KimiProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCookieService: KimiBrowserCookieService()
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.rawMeta["kimi.authSource"], "manual")
    }

    func testJWTExpiryValidation() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let futureToken = jwt(exp: Int(now.timeIntervalSince1970) + 3600)
        let pastToken = jwt(exp: Int(now.timeIntervalSince1970) - 10)

        XCTAssertFalse(KimiJWT.isExpired(futureToken, now: now))
        XCTAssertTrue(KimiJWT.isExpired(pastToken, now: now))
        XCTAssertTrue(KimiJWT.isExpired("invalid.jwt", now: now))
    }

    private func makeDescriptor(threshold: Double = 10) -> ProviderDescriptor {
        ProviderDescriptor(
            id: "kimi-coding",
            name: "Kimi (For Coding)",
            type: .kimi,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: threshold, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .bearer, keychainService: "AIBalanceMonitor", keychainAccount: "kimi.com/kimi-auth-manual"),
            baseURL: "https://www.kimi.com",
            kimiConfig: KimiProviderConfig(
                authMode: .manual,
                manualTokenAccount: "kimi.com/kimi-auth-manual",
                autoCookieEnabled: true,
                browserOrder: [.arc, .chrome, .safari, .edge, .brave, .chromium]
            )
        )
    }

    private func jwt(exp: Int) -> String {
        let header = #"{"alg":"HS256","typ":"JWT"}"#
        let payload = #"{"exp":\#(exp)}"#
        return "\(b64url(header)).\(b64url(payload)).signature"
    }

    private func b64url(_ input: String) -> String {
        Data(input.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
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
