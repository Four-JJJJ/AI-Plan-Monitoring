import Foundation
import XCTest
@testable import AIPlanMonitor

final class AppUpdateServiceReleaseNotesTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        AppUpdateReleaseNotesMockURLProtocol.requestHandler = nil
    }

    func testFetchReleaseNotesBodyUsesVPrefixedTagFirst() async throws {
        let service = makeService()

        AppUpdateReleaseNotesMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/repos/bddiudiu/AI-Plan-Monitor/releases/tags/v2.1.0")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"body":"## Changes\n- Added release notes popup"}"#.utf8))
        }

        let body = try await service.fetchReleaseNotesBody(forVersion: "2.1.0")
        XCTAssertEqual(body, "## Changes\n- Added release notes popup")
    }

    func testFetchReleaseNotesBodyFallsBackToBareVersionTag() async throws {
        let service = makeService()
        var visitedPaths: [String] = []

        AppUpdateReleaseNotesMockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            visitedPaths.append(path)
            if path.hasSuffix("/tags/v2.1.0") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }

            XCTAssertEqual(path, "/repos/bddiudiu/AI-Plan-Monitor/releases/tags/2.1.0")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"body":"Plain tag release notes"}"#.utf8))
        }

        let body = try await service.fetchReleaseNotesBody(forVersion: "2.1.0")
        XCTAssertEqual(body, "Plain tag release notes")
        XCTAssertEqual(
            visitedPaths,
            [
                "/repos/bddiudiu/AI-Plan-Monitor/releases/tags/v2.1.0",
                "/repos/bddiudiu/AI-Plan-Monitor/releases/tags/2.1.0"
            ]
        )
    }

    func testReleaseTagCandidatesDeduplicateNormalizedVersion() {
        XCTAssertEqual(
            AppUpdateService.releaseTagCandidates(forVersion: "v2.1.0"),
            ["v2.1.0", "2.1.0"]
        )
    }

    private func makeService() -> AppUpdateService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppUpdateReleaseNotesMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return AppUpdateService(session: session)
    }
}

private final class AppUpdateReleaseNotesMockURLProtocol: URLProtocol {
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
