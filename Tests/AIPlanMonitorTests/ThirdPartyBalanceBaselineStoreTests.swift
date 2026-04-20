import XCTest
@testable import AIPlanMonitor

final class ThirdPartyBalanceBaselineStoreTests: XCTestCase {
    func testSaveAndLoadEntries() {
        let (store, fileURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var tracker = ThirdPartyBalanceBaselineTracker()
        _ = tracker.record(remaining: 1000, for: "relay-a", at: Date(timeIntervalSince1970: 1))
        _ = tracker.record(remaining: 600, for: "relay-a", at: Date(timeIntervalSince1970: 2))
        _ = tracker.record(remaining: 300, for: "relay-b", at: Date(timeIntervalSince1970: 3))

        store.save(tracker.snapshotEntries())
        let loaded = store.load()

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded["relay-a"]?.baseline, 1000)
        XCTAssertEqual(loaded["relay-a"]?.lastRemaining, 600)
        XCTAssertEqual(loaded["relay-b"]?.baseline, 300)
    }

    func testSaveAfterPruneKeepsOnlyTargetProviders() {
        let (store, fileURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var tracker = ThirdPartyBalanceBaselineTracker()
        _ = tracker.record(remaining: 100, for: "relay-1", at: Date(timeIntervalSince1970: 1))
        _ = tracker.record(remaining: 100, for: "relay-2", at: Date(timeIntervalSince1970: 2))
        _ = tracker.record(remaining: 100, for: "relay-3", at: Date(timeIntervalSince1970: 3))
        tracker.prune(keepingProviderIDs: Set(["relay-2", "relay-3"]), maxEntries: 2)

        store.save(tracker.snapshotEntries())
        let loaded = store.load()

        XCTAssertEqual(Set(loaded.keys), Set(["relay-2", "relay-3"]))
    }

    func testResetClearsPersistedEntries() {
        let (store, fileURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var tracker = ThirdPartyBalanceBaselineTracker()
        _ = tracker.record(remaining: 1000, for: "relay-a", at: Date(timeIntervalSince1970: 1))
        store.save(tracker.snapshotEntries())
        XCTAssertFalse(store.load().isEmpty)

        store.reset()

        XCTAssertTrue(store.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    private func makeStore() -> (ThirdPartyBalanceBaselineStore, URL) {
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("third-party-baseline-store-\(UUID().uuidString).json")
        return (ThirdPartyBalanceBaselineStore(fileURL: fileURL), fileURL)
    }
}
