import XCTest
@testable import AIPlanMonitor

final class AppViewModelProviderFailureTests: XCTestCase {
    func testOfficialFailureBuildsEmptySnapshotWithAuthExpired() {
        let descriptor = ProviderDescriptor.defaultOfficialCopilot()
        let snapshot = AppViewModel.emptySnapshotForFetchFailure(
            descriptor: descriptor,
            health: .authExpired,
            message: "Unauthorized"
        )

        XCTAssertEqual(snapshot?.source, "copilot-official")
        XCTAssertEqual(snapshot?.status, .error)
        XCTAssertEqual(snapshot?.fetchHealth, .authExpired)
        XCTAssertEqual(snapshot?.valueFreshness, .empty)
        XCTAssertEqual(snapshot?.diagnosticCode, "auth-expired")
        XCTAssertEqual(snapshot?.sourceLabel, "Official")
    }

    func testRelayFailureBuildsEmptySnapshotWithRelayUnit() {
        let descriptor = ProviderDescriptor.defaultOpenAilinyu()
        let snapshot = AppViewModel.emptySnapshotForFetchFailure(
            descriptor: descriptor,
            health: .endpointMisconfigured,
            message: "Invalid endpoint"
        )

        XCTAssertEqual(snapshot?.source, "open-ailinyu")
        XCTAssertEqual(snapshot?.status, .error)
        XCTAssertEqual(snapshot?.fetchHealth, .endpointMisconfigured)
        XCTAssertEqual(snapshot?.valueFreshness, .empty)
        XCTAssertEqual(snapshot?.diagnosticCode, "endpoint-misconfigured")
        XCTAssertEqual(snapshot?.sourceLabel, "Third-Party")
        XCTAssertEqual(snapshot?.unit, "quota")
    }
}
