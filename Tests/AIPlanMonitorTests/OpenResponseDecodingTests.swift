import XCTest
@testable import AIPlanMonitor

final class OpenResponseDecodingTests: XCTestCase {
    func testDecodeTokenUsageEnvelope() throws {
        let json = #"{"code":true,"data":{"expires_at":0,"name":"OpenClaw","object":"token_usage","total_available":-2567608849,"total_granted":0,"total_used":2567608849,"unlimited_quota":true},"message":"ok"}"#
        let decoded = try JSONDecoder().decode(OpenTokenUsageEnvelope.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.data.name, "OpenClaw")
        XCTAssertTrue(decoded.data.unlimitedQuota)
        XCTAssertEqual(decoded.data.totalUsed, 2_567_608_849)
    }

    func testDecodeBillingUsage() throws {
        let json = #"{"object":"list","total_usage":513521.7698}"#
        let decoded = try JSONDecoder().decode(OpenBillingUsage.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.object, "list")
        XCTAssertEqual(decoded.totalUsage, 513_521.7698)
    }
}
