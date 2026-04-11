import XCTest
@testable import AIBalanceMonitor

final class CodexAccountSlotStoreTests: XCTestCase {
    func testAccountKeyPriority() {
        var snapshot = makeSnapshot(accountID: "acc-1", accountLabel: "a@test.com", subject: "sub-1")
        XCTAssertEqual(CodexAccountSlotStore.accountKey(from: snapshot), "account:acc-1")

        snapshot = makeSnapshot(accountID: nil, accountLabel: "a@test.com", subject: "sub-1")
        XCTAssertEqual(CodexAccountSlotStore.accountKey(from: snapshot), "email:a@test.com")

        snapshot = makeSnapshot(accountID: nil, accountLabel: nil, subject: "sub-1")
        XCTAssertEqual(CodexAccountSlotStore.accountKey(from: snapshot), "subject:sub-1")

        snapshot = makeSnapshot(accountID: nil, accountLabel: nil, subject: nil)
        XCTAssertEqual(CodexAccountSlotStore.accountKey(from: snapshot), "unknown")
    }

    func testTwoSlotReplacementUsesLeastRecentlyActive() throws {
        let store = makeStore(staleInterval: 10_000)
        let base = Date(timeIntervalSince1970: 1_000)

        _ = store.upsertActive(snapshot: makeSnapshot(accountID: "a"), now: base)
        _ = store.upsertActive(snapshot: makeSnapshot(accountID: "b"), now: base.addingTimeInterval(10))
        let slots = store.upsertActive(snapshot: makeSnapshot(accountID: "c"), now: base.addingTimeInterval(20))

        XCTAssertEqual(slots.count, 2)
        let keys = Set(slots.map(\.accountKey))
        XCTAssertTrue(keys.contains("account:b"))
        XCTAssertTrue(keys.contains("account:c"))
        XCTAssertFalse(keys.contains("account:a"))
    }

    func testSwitchKeepsInactiveSlotSnapshotForCountdown() throws {
        let store = makeStore(staleInterval: 10_000)
        let base = Date(timeIntervalSince1970: 2_000)

        let aSnap = makeSnapshot(accountID: "a", sessionReset: base.addingTimeInterval(1_800))
        _ = store.upsertActive(snapshot: aSnap, now: base)
        let bSnap = makeSnapshot(accountID: "b", sessionReset: base.addingTimeInterval(3_600))
        let slots = store.upsertActive(snapshot: bSnap, now: base.addingTimeInterval(60))

        XCTAssertEqual(slots.count, 2)
        let inactive = slots.first(where: { $0.accountKey == "account:a" })
        XCTAssertNotNil(inactive)
        XCTAssertEqual(inactive?.isActive, false)
        XCTAssertEqual(inactive?.lastSnapshot.quotaWindows.first?.resetAt, aSnap.quotaWindows.first?.resetAt)
    }

    func testUnknownIdentityUsesSingleSlot() throws {
        let store = makeStore(staleInterval: 10_000)
        let base = Date(timeIntervalSince1970: 3_000)

        _ = store.upsertActive(snapshot: makeSnapshot(accountID: nil, accountLabel: nil, subject: nil), now: base)
        let slots = store.upsertActive(snapshot: makeSnapshot(accountID: nil, accountLabel: nil, subject: nil), now: base.addingTimeInterval(10))
        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots.first?.accountKey, "unknown")
    }

    func testStaleSlotsAreHidden() throws {
        let store = makeStore(staleInterval: 100)
        let now = Date(timeIntervalSince1970: 4_000)
        _ = store.upsertActive(snapshot: makeSnapshot(accountID: "a"), now: now.addingTimeInterval(-500))

        let visible = store.visibleSlots(now: now)
        XCTAssertTrue(visible.isEmpty)
    }

    private func makeStore(staleInterval: TimeInterval) -> CodexAccountSlotStore {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-slot-tests-\(UUID().uuidString).json")
        return CodexAccountSlotStore(staleInterval: staleInterval, fileURL: path)
    }

    private func makeSnapshot(
        accountID: String?,
        accountLabel: String? = nil,
        subject: String? = nil,
        sessionReset: Date? = nil
    ) -> UsageSnapshot {
        var rawMeta: [String: String] = [:]
        if let accountID { rawMeta["codex.accountId"] = accountID }
        if let subject { rawMeta["codex.subject"] = subject }
        if let accountLabel { rawMeta["codex.accountLabel"] = accountLabel }

        return UsageSnapshot(
            source: "codex-official",
            status: .ok,
            remaining: 30,
            used: 70,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "test",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "session",
                    title: "5h",
                    remainingPercent: 30,
                    usedPercent: 70,
                    resetAt: sessionReset,
                    kind: .session
                ),
                UsageQuotaWindow(
                    id: "weekly",
                    title: "Weekly",
                    remainingPercent: 60,
                    usedPercent: 40,
                    resetAt: sessionReset?.addingTimeInterval(86_400),
                    kind: .weekly
                ),
            ],
            sourceLabel: "API",
            accountLabel: accountLabel,
            extras: [:],
            rawMeta: rawMeta
        )
    }
}
