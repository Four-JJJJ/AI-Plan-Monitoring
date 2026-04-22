import Foundation
import XCTest
@testable import AIPlanMonitor

final class OpenCodeGoProviderTests: XCTestCase {
    func testParseRemoteStreamingBodyBuildsThreeWindows() throws {
        let now = try makeDate("2026-04-23T12:00:00Z")
        let body = #"""
        ;0x00000128;((self.$R=self.$R||{})["server-fn:11"]=[],($R=>$R[0]={mine:!0,useBalance:!1,rollingUsage:$R[1]={status:"ok",resetInSec:600,usagePercent:12},weeklyUsage:$R[2]={status:"ok",resetInSec:3600,usagePercent:40},monthlyUsage:$R[3]={status:"ok",resetInSec:7200,usagePercent:65}})($R["server-fn:11"]))
        """#

        let snapshot = try OpenCodeGoProvider.parseRemoteSnapshot(
            body: body,
            descriptor: ProviderDescriptor.defaultOfficialOpenCodeGo(),
            now: now
        )

        XCTAssertEqual(snapshot.sourceLabel, "Remote")
        XCTAssertEqual(snapshot.quotaWindows.count, 3)

        let session = try XCTUnwrap(snapshot.quotaWindows.first(where: { $0.kind == .session }))
        XCTAssertEqual(session.title, "Session")
        XCTAssertEqual(session.usedPercent, 12, accuracy: 0.001)
        XCTAssertEqual(session.remainingPercent, 88, accuracy: 0.001)
        XCTAssertEqual(session.resetAt, now.addingTimeInterval(600))

        let weekly = try XCTUnwrap(snapshot.quotaWindows.first(where: { $0.kind == .weekly }))
        XCTAssertEqual(weekly.usedPercent, 40, accuracy: 0.001)
        XCTAssertEqual(weekly.resetAt, now.addingTimeInterval(3600))

        let monthly = try XCTUnwrap(snapshot.quotaWindows.first(where: { $0.title == "Monthly" }))
        XCTAssertEqual(monthly.kind, .custom)
        XCTAssertEqual(monthly.usedPercent, 65, accuracy: 0.001)
        XCTAssertEqual(monthly.resetAt, now.addingTimeInterval(7200))
    }

    func testFetchFallsBackToLocalWhenRemoteStatusCodeFails() async throws {
        let now = try makeDate("2026-04-23T12:00:00Z")
        let localRows = [
            OpenCodeGoProvider.LocalUsageRow(createdMs: now.addingTimeInterval(-3600).timeIntervalSince1970 * 1000, cost: 3.0)
        ]

        for code in [302, 401, 403, 500] {
            let (provider, resetMock) = makeProvider(
                now: now,
                localRows: localRows
            ) { request in
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: code,
                    httpVersion: nil,
                    headerFields: code == 302 ? ["Location": "/login"] : nil
                )!
                return (response, Data())
            }
            defer { resetMock() }

            let snapshot = try await provider.fetch(forceRefresh: true)
            XCTAssertEqual(snapshot.sourceLabel, "Local Fallback")
            XCTAssertEqual(snapshot.valueFreshness, .cachedFallback)
            XCTAssertEqual(snapshot.extras["truthSource"], "local-fallback")
        }
    }

    func testFetchFallsBackToLocalWhenRemoteBodyCannotBeParsed() async throws {
        let now = try makeDate("2026-04-23T12:00:00Z")
        let localRows = [
            OpenCodeGoProvider.LocalUsageRow(createdMs: now.addingTimeInterval(-1800).timeIntervalSince1970 * 1000, cost: 1.2)
        ]

        let (provider, resetMock) = makeProvider(
            now: now,
            localRows: localRows
        ) { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("invalid-stream-body".utf8))
        }
        defer { resetMock() }

        let snapshot = try await provider.fetch(forceRefresh: true)
        XCTAssertEqual(snapshot.sourceLabel, "Local Fallback")
        XCTAssertEqual(snapshot.valueFreshness, .cachedFallback)
        XCTAssertEqual(snapshot.extras["fallbackReason"], "parse")
    }

    func testBuildLocalWindowsRespectsFiveHourUtcWeekAndAnchoredMonth() throws {
        let now = try makeDate("2026-04-23T12:00:00Z")
        let rows = [
            OpenCodeGoProvider.LocalUsageRow(createdMs: try makeMillis("2026-03-15T08:00:00Z"), cost: 2),
            OpenCodeGoProvider.LocalUsageRow(createdMs: try makeMillis("2026-04-14T10:00:00Z"), cost: 7),
            OpenCodeGoProvider.LocalUsageRow(createdMs: try makeMillis("2026-04-16T09:00:00Z"), cost: 4),
            OpenCodeGoProvider.LocalUsageRow(createdMs: try makeMillis("2026-04-20T10:00:00Z"), cost: 3),
            OpenCodeGoProvider.LocalUsageRow(createdMs: try makeMillis("2026-04-23T10:00:00Z"), cost: 6)
        ]

        let windows = OpenCodeGoProvider.buildLocalWindows(
            rows: rows,
            descriptorID: "opencode-go-official",
            now: now
        )

        let session = try XCTUnwrap(windows.first(where: { $0.kind == .session }))
        XCTAssertEqual(session.usedPercent, 50, accuracy: 0.001)
        XCTAssertEqual(session.resetAt, try makeDate("2026-04-23T15:00:00Z"))

        let weekly = try XCTUnwrap(windows.first(where: { $0.kind == .weekly }))
        XCTAssertEqual(weekly.usedPercent, 30, accuracy: 0.001)
        XCTAssertEqual(weekly.resetAt, try makeDate("2026-04-27T00:00:00Z"))

        let monthly = try XCTUnwrap(windows.first(where: { $0.title == "Monthly" }))
        XCTAssertEqual(monthly.usedPercent, 21.6667, accuracy: 0.001)
        XCTAssertEqual(monthly.resetAt, try makeDate("2026-05-15T08:00:00Z"))
    }

    func testDetectionRequiresAtLeastOneSignal() {
        XCTAssertFalse(
            OpenCodeGoProvider.isDetected(
                workspaceID: nil,
                cookieHeader: nil,
                hasLocalHistory: false
            )
        )
        XCTAssertTrue(
            OpenCodeGoProvider.isDetected(
                workspaceID: "wrk_test",
                cookieHeader: nil,
                hasLocalHistory: false
            )
        )
        XCTAssertTrue(
            OpenCodeGoProvider.isDetected(
                workspaceID: nil,
                cookieHeader: "auth=test_cookie",
                hasLocalHistory: false
            )
        )
        XCTAssertTrue(
            OpenCodeGoProvider.isDetected(
                workspaceID: nil,
                cookieHeader: nil,
                hasLocalHistory: true
            )
        )
    }

    private func makeProvider(
        now: Date,
        localRows: [OpenCodeGoProvider.LocalUsageRow],
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (OpenCodeGoProvider, () -> Void) {
        let workspaceAccount = "official/opencode-go/workspace-id-\(UUID().uuidString)"
        let cookieAccount = "official/opencode-go/auth-cookie-\(UUID().uuidString)"

        let keychain = KeychainService()
        XCTAssertTrue(
            keychain.saveToken(
                "wrk_test_workspace",
                service: KeychainService.defaultServiceName,
                account: workspaceAccount
            )
        )
        XCTAssertTrue(
            keychain.saveToken(
                "auth=test_cookie",
                service: KeychainService.defaultServiceName,
                account: cookieAccount
            )
        )

        var descriptor = ProviderDescriptor.defaultOfficialOpenCodeGo()
        descriptor.auth = AuthConfig(
            kind: .none,
            keychainService: KeychainService.defaultServiceName,
            keychainAccount: workspaceAccount
        )
        descriptor.officialConfig?.sourceMode = .web
        descriptor.officialConfig?.webMode = .manual
        descriptor.officialConfig?.manualCookieAccount = cookieAccount

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenCodeGoMockURLProtocol.self]
        let session = URLSession(configuration: config)
        OpenCodeGoMockURLProtocol.requestHandler = handler

        let provider = OpenCodeGoProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCookieService: BrowserCookieService(),
            nowProvider: { now },
            localRowsProvider: { localRows }
        )
        return (provider, { OpenCodeGoMockURLProtocol.requestHandler = nil })
    }

    private func makeDate(_ iso: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else {
            throw ProviderError.invalidResponse("invalid test date: \(iso)")
        }
        return date
    }

    private func makeMillis(_ iso: String) throws -> Double {
        try makeDate(iso).timeIntervalSince1970 * 1000
    }
}

private final class OpenCodeGoMockURLProtocol: URLProtocol {
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
