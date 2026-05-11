import OhMyUsageApplication
import XCTest
@testable import OhMyUsage

final class SettingsResourceDiagnosticsPresenterTests: XCTestCase {
    func testPresentationSummarizesRuntimeCounters() {
        let diagnostics = RuntimeMemoryDiagnostics(
            residentSizeBytes: 42 * 1024 * 1024,
            snapshotCount: 7,
            codexProfileCount: 2,
            codexSlotCount: 3,
            claudeProfileCount: 1,
            claudeSlotCount: 2,
            codexPrefetchAttemptedIdentityCount: 4,
            codexPrefetchInFlightCount: 1,
            claudePrefetchAttemptedIdentityCount: 5,
            claudePrefetchInFlightCount: 2,
            pollTaskCount: 3,
            enabledProviderCount: 6,
            providerErrorCount: 2,
            consecutiveFailureTotal: 5
        )

        let presentation = SettingsResourceDiagnosticsPresenter.presentation(
            diagnostics: diagnostics,
            localizedText: Self.english
        )

        XCTAssertEqual(presentation.title, "Overview")
        XCTAssertEqual(presentation.rows.map(\.id), ["snapshots", "polls", "health", "profiles", "prefetch"])
        XCTAssertEqual(presentation.rows.first(where: { $0.id == "health" })?.value, "4/6")
        XCTAssertEqual(
            presentation.rows.first(where: { $0.id == "health" })?.detail,
            "Healthy providers · 2 in error"
        )
        XCTAssertEqual(presentation.rows.first(where: { $0.id == "profiles" })?.value, "3")
        XCTAssertEqual(presentation.rows.first(where: { $0.id == "prefetch" })?.value, "3")
    }

    private static func english(_ zhHans: String, _ english: String) -> String {
        english
    }
}
