import XCTest
@testable import AIPlanMonitor

final class ClaudeAccountSlotStoreTests: XCTestCase {
    func testAccountKeyPriority() {
        var snapshot = makeSnapshot(email: "user@example.com", fingerprint: "abc12345")
        snapshot.rawMeta["claude.accountKey"] = "Custom:Key"
        XCTAssertEqual(ClaudeAccountSlotStore.accountKey(from: snapshot), "custom:key")

        snapshot = makeSnapshot(email: "user@example.com", fingerprint: "abc12345")
        XCTAssertEqual(ClaudeAccountSlotStore.accountKey(from: snapshot), "fingerprint:abc12345")

        snapshot = makeSnapshot(email: "user@example.com", fingerprint: nil)
        XCTAssertEqual(ClaudeAccountSlotStore.accountKey(from: snapshot), "email:user@example.com")

        snapshot = makeSnapshot(email: nil, fingerprint: nil)
        XCTAssertEqual(ClaudeAccountSlotStore.accountKey(from: snapshot), "unknown")
    }

    func testSameEmailDifferentFingerprintKeepsSeparateSlots() throws {
        let store = makeStore(staleInterval: 10_000)
        let base = Date(timeIntervalSince1970: 2_000)

        _ = store.upsertActive(
            snapshot: makeSnapshot(
                email: "shared@example.com",
                fingerprint: "finger-a",
                sessionReset: base.addingTimeInterval(1_800)
            ),
            now: base
        )
        let slots = store.upsertActive(
            snapshot: makeSnapshot(
                email: "shared@example.com",
                fingerprint: "finger-b",
                sessionReset: base.addingTimeInterval(3_600)
            ),
            now: base.addingTimeInterval(30)
        )

        XCTAssertEqual(slots.count, 2)
        XCTAssertEqual(
            Set(slots.map(\.accountKey)),
            ["fingerprint:finger-a", "fingerprint:finger-b"]
        )
        XCTAssertEqual(Set(slots.map(\.slotID.rawValue)), ["A", "B"])
    }

    func testUnknownIdentityUsesSingleSlot() throws {
        let store = makeStore(staleInterval: 10_000)
        let base = Date(timeIntervalSince1970: 3_000)

        _ = store.upsertActive(snapshot: makeSnapshot(email: nil, fingerprint: nil), now: base)
        let slots = store.upsertActive(snapshot: makeSnapshot(email: nil, fingerprint: nil), now: base.addingTimeInterval(10))

        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots.first?.accountKey, "unknown")
    }

    func testSwitchKeepsInactiveSlotSnapshotForCountdown() throws {
        let store = makeStore(staleInterval: 10_000)
        let base = Date(timeIntervalSince1970: 4_000)

        let aSnapshot = makeSnapshot(
            email: "a@example.com",
            fingerprint: "finger-a",
            sessionReset: base.addingTimeInterval(1_200)
        )
        _ = store.upsertActive(snapshot: aSnapshot, now: base)

        let bSnapshot = makeSnapshot(
            email: "b@example.com",
            fingerprint: "finger-b",
            sessionReset: base.addingTimeInterval(2_400)
        )
        let slots = store.upsertActive(snapshot: bSnapshot, now: base.addingTimeInterval(20))

        XCTAssertEqual(slots.count, 2)
        let inactive = slots.first(where: { $0.accountKey == "fingerprint:finger-a" })
        XCTAssertNotNil(inactive)
        XCTAssertEqual(inactive?.isActive, false)
        XCTAssertEqual(inactive?.lastSnapshot.quotaWindows.first?.resetAt, aSnapshot.quotaWindows.first?.resetAt)
    }

    func testExplicitSlotIDIsHonored() throws {
        let store = makeStore(staleInterval: 10_000)
        let base = Date(timeIntervalSince1970: 5_000)
        var snapshot = makeSnapshot(email: "slot@example.com", fingerprint: "finger-slot")
        snapshot.rawMeta["claude.slotID"] = "D"

        let slots = store.upsertActive(snapshot: snapshot, now: base)

        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots.first?.slotID.rawValue, "D")
    }

    private func makeStore(staleInterval: TimeInterval) -> ClaudeAccountSlotStore {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-slot-tests-\(UUID().uuidString).json")
        return ClaudeAccountSlotStore(staleInterval: staleInterval, fileURL: path)
    }

    private func makeSnapshot(
        email: String?,
        fingerprint: String?,
        sessionReset: Date? = nil
    ) -> UsageSnapshot {
        var rawMeta: [String: String] = [:]
        if let email {
            rawMeta["claude.accountLabel"] = email
        }
        if let fingerprint {
            rawMeta["claude.credentialFingerprint"] = fingerprint
        }

        return UsageSnapshot(
            source: "claude-official",
            status: .ok,
            remaining: 45,
            used: 55,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "test",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "session",
                    title: "5h",
                    remainingPercent: 45,
                    usedPercent: 55,
                    resetAt: sessionReset,
                    kind: .session
                ),
                UsageQuotaWindow(
                    id: "weekly",
                    title: "Weekly",
                    remainingPercent: 65,
                    usedPercent: 35,
                    resetAt: sessionReset?.addingTimeInterval(86_400),
                    kind: .weekly
                )
            ],
            sourceLabel: "API",
            accountLabel: email,
            extras: [:],
            rawMeta: rawMeta
        )
    }
}
