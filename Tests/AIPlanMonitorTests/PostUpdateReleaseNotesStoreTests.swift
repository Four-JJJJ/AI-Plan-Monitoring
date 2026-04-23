import Foundation
import XCTest
@testable import AIPlanMonitor

final class PostUpdateReleaseNotesStoreTests: XCTestCase {
    func testConsumeReturnsPendingReleaseNotesWhenCurrentVersionMatches() {
        let defaults = UserDefaults(suiteName: "PostUpdateReleaseNotesStoreTests.match.\(UUID().uuidString)")!
        let store = PostUpdateReleaseNotesStore(defaults: defaults)

        store.schedulePresentation(for: makeUpdate(version: "2.1.0"))

        let pending = store.consumePresentationIfNeeded(currentVersion: "2.1.0")

        XCTAssertEqual(pending?.version, "2.1.0")
        XCTAssertEqual(pending?.displayURL, URL(string: "https://example.com/notes/2.1.0")!)
        XCTAssertNil(store.consumePresentationIfNeeded(currentVersion: "2.1.0"))
    }

    func testConsumeKeepsPendingReleaseNotesWhenCurrentVersionIsOlder() {
        let defaults = UserDefaults(suiteName: "PostUpdateReleaseNotesStoreTests.older.\(UUID().uuidString)")!
        let store = PostUpdateReleaseNotesStore(defaults: defaults)

        store.schedulePresentation(for: makeUpdate(version: "2.1.0"))

        XCTAssertNil(store.consumePresentationIfNeeded(currentVersion: "2.0.9"))
        XCTAssertEqual(
            store.consumePresentationIfNeeded(currentVersion: "2.1.0")?.version,
            "2.1.0"
        )
    }

    func testConsumeDropsStalePendingReleaseNotesWhenCurrentVersionIsNewer() {
        let defaults = UserDefaults(suiteName: "PostUpdateReleaseNotesStoreTests.newer.\(UUID().uuidString)")!
        let store = PostUpdateReleaseNotesStore(defaults: defaults)

        store.schedulePresentation(for: makeUpdate(version: "2.1.0"))

        XCTAssertNil(store.consumePresentationIfNeeded(currentVersion: "2.2.0"))
        XCTAssertNil(store.consumePresentationIfNeeded(currentVersion: "2.1.0"))
    }

    private func makeUpdate(version: String) -> AppUpdateInfo {
        AppUpdateInfo(
            latestVersion: version,
            releaseURL: URL(string: "https://example.com/releases/\(version)")!,
            notesURL: URL(string: "https://example.com/notes/\(version)")!,
            publishedAt: nil,
            zipAsset: nil,
            dmgAsset: nil
        )
    }
}
