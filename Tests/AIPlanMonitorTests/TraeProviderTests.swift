import Foundation
import XCTest
@testable import AIPlanMonitor

final class TraeProviderTests: XCTestCase {
    func testParseSnapshotParsesDollarAndAutocompleteWindows() throws {
        let json = """
        {
          "code": 0,
          "msg": "success",
          "data": {
            "user_entitlement_pack_list": [
              {
                "display_desc": "Trae SOLO Pro",
                "usage": {
                  "basic_usage_amount": 12.5,
                  "auto_completion_usage": 8
                },
                "entitlement_base_info": {
                  "end_time": 1776787199,
                  "quota": {
                    "basic_usage_limit": 100,
                    "auto_completion_limit": 50
                  }
                }
              }
            ]
          }
        }
        """

        let snapshot = try TraeProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: ProviderDescriptor.defaultOfficialTrae()
        )

        XCTAssertEqual(snapshot.sourceLabel, "API")
        XCTAssertEqual(snapshot.extras["planType"], "Trae SOLO Pro")
        XCTAssertTrue(snapshot.note.contains("Plan Trae SOLO Pro"))
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.title == "美元余额" })?.remainingPercent ?? -1,
            87.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.title == "自动补全" })?.remainingPercent ?? -1,
            84.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.title == "美元余额" })?.resetAt,
            Date(timeIntervalSince1970: 1_776_787_199)
        )
    }

    func testParseSnapshotStripsPlanKeywordFromDisplayDesc() throws {
        let json = """
        {
          "code": 0,
          "msg": "success",
          "data": {
            "user_entitlement_pack_list": [
              {
                "display_desc": "Free plan",
                "usage": {
                  "basic_usage_amount": 1,
                  "auto_completion_usage": 10
                },
                "entitlement_base_info": {
                  "end_time": 1776787199,
                  "quota": {
                    "basic_usage_limit": 3,
                    "auto_completion_limit": 100
                  }
                }
              }
            ]
          }
        }
        """

        let snapshot = try TraeProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: ProviderDescriptor.defaultOfficialTrae()
        )

        XCTAssertEqual(snapshot.extras["planType"], "Free")
        XCTAssertTrue(snapshot.note.contains("Plan Free"))
        XCTAssertTrue(snapshot.note.contains("美元余额"))
        XCTAssertTrue(snapshot.note.contains("自动补全"))
    }

    func testParseSnapshotKeepsDisplayDescWithoutPlanKeyword() throws {
        let json = """
        {
          "code": 0,
          "msg": "success",
          "data": {
            "user_entitlement_pack_list": [
              {
                "display_desc": "Ultra",
                "usage": {
                  "basic_usage_amount": 1,
                  "auto_completion_usage": 10
                },
                "entitlement_base_info": {
                  "end_time": 1776787199,
                  "quota": {
                    "basic_usage_limit": 3,
                    "auto_completion_limit": 100
                  }
                }
              }
            ]
          }
        }
        """

        let snapshot = try TraeProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: ProviderDescriptor.defaultOfficialTrae()
        )

        XCTAssertEqual(snapshot.extras["planType"], "Ultra")
        XCTAssertTrue(snapshot.note.contains("Plan Ultra"))
    }

    func testFetchMaps401And403ToUnauthorized() async throws {
        try await assertFetchError(
            statusCode: 401,
            body: #"{"msg":"unauthorized"}"#,
            matcher: {
                if case .unauthorized = $0 {
                    return true
                }
                return false
            }
        )

        try await assertFetchError(
            statusCode: 403,
            body: #"{"msg":"forbidden"}"#,
            matcher: {
                if case .unauthorized = $0 {
                    return true
                }
                return false
            }
        )
    }

    func testFetchMaps429ToRateLimited() async throws {
        try await assertFetchError(
            statusCode: 429,
            body: #"{"msg":"too many requests"}"#,
            matcher: {
                if case .rateLimited = $0 {
                    return true
                }
                return false
            }
        )
    }

    func testFetchMapsMissingFieldsToInvalidResponse() async throws {
        try await assertFetchError(
            statusCode: 200,
            body: #"{"code":0,"data":{"user_entitlement_pack_list":[{"usage":{"basic_usage_amount":1}}]}}"#,
            matcher: {
                if case .invalidResponse = $0 {
                    return true
                }
                return false
            }
        )
    }

    func testNormalizeTokenAcceptsCloudIDEAndBearerPrefix() {
        let jwt = "aaa.bbb.ccc"

        XCTAssertEqual(TraeProvider.normalizeToken(jwt), jwt)
        XCTAssertEqual(TraeProvider.normalizeToken("Cloud-IDE-JWT \(jwt)"), jwt)
        XCTAssertEqual(TraeProvider.normalizeToken("cloud-ide-jwt \(jwt)"), jwt)
        XCTAssertEqual(TraeProvider.normalizeToken("Bearer \(jwt)"), jwt)
    }

    private func assertFetchError(
        statusCode: Int,
        body: String,
        matcher: (ProviderError) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let keychain = KeychainService()
        let service = "AIPlanMonitorTests-Trae-\(UUID().uuidString)"
        let account = "official/trae/cloud-ide-jwt-\(UUID().uuidString)"
        XCTAssertTrue(
            keychain.saveToken("Bearer aaa.bbb.ccc", service: service, account: account),
            file: file,
            line: line
        )

        var descriptor = ProviderDescriptor.defaultOfficialTrae()
        descriptor.auth = AuthConfig(kind: .bearer, keychainService: service, keychainAccount: account)
        descriptor.baseURL = "https://api-sg-central.trae.ai"
        descriptor.officialConfig?.sourceMode = .auto

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TraeMockURLProtocol.self]
        let session = URLSession(configuration: config)

        TraeMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/trae/api/v1/pay/ide_user_ent_usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Cloud-IDE-JWT aaa.bbb.ccc")
            let response = HTTPURLResponse(
                url: URL(string: "https://api-sg-central.trae.ai/trae/api/v1/pay/ide_user_ent_usage")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(body.utf8))
        }
        defer { TraeMockURLProtocol.requestHandler = nil }

        let provider = TraeProvider(descriptor: descriptor, session: session, keychain: keychain)
        do {
            _ = try await provider.fetch()
            XCTFail("Expected ProviderError", file: file, line: line)
        } catch let error as ProviderError {
            XCTAssertTrue(matcher(error), "Unexpected ProviderError: \(error)", file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private final class TraeMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

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
