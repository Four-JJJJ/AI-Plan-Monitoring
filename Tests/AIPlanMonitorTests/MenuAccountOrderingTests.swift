import Foundation
import XCTest
@testable import AIPlanMonitor

@MainActor
final class MenuAccountOrderingTests: XCTestCase {
    func testCodexMenuSortingPrioritizesActiveThenAscendingSlotID() {
        let slotJ = CodexSlotID.generated(index: 9)
        let slotE = CodexSlotID.generated(index: 4)
        let slotC = CodexSlotID.generated(index: 2)
        let slots = [
            makeCodexSlot(slotID: slotJ, isActive: false),
            makeCodexSlot(slotID: slotE, isActive: false),
            makeCodexSlot(slotID: .b, isActive: true),
            makeCodexSlot(slotID: .a, isActive: false),
            makeCodexSlot(slotID: slotC, isActive: false)
        ]

        let ordered = AppViewModel.sortedCodexSlotsForMenu(slots)

        XCTAssertEqual(ordered.map(\.slotID), [.b, .a, slotC, slotE, slotJ])
    }

    func testClaudeMenuSortingPrioritizesActiveThenAscendingSlotID() {
        let slotH = CodexSlotID.generated(index: 7)
        let slotD = CodexSlotID.generated(index: 3)
        let slotG = CodexSlotID.generated(index: 6)
        let slots = [
            makeClaudeSlot(slotID: slotH, isActive: false),
            makeClaudeSlot(slotID: slotD, isActive: true),
            makeClaudeSlot(slotID: slotG, isActive: false),
            makeClaudeSlot(slotID: .a, isActive: false)
        ]

        let ordered = AppViewModel.sortedClaudeSlotsForMenu(slots)

        XCTAssertEqual(ordered.map(\.slotID), [slotD, .a, slotG, slotH])
    }

    private func makeCodexSlot(slotID: CodexSlotID, isActive: Bool) -> CodexAccountSlot {
        CodexAccountSlot(
            slotID: slotID,
            accountKey: "account-\(slotID.rawValue)",
            displayName: "Codex \(slotID.rawValue)",
            lastSnapshot: makeSnapshot(label: "codex-\(slotID.rawValue)"),
            lastSeenAt: Date(timeIntervalSince1970: 1_000),
            isActive: isActive
        )
    }

    private func makeClaudeSlot(slotID: CodexSlotID, isActive: Bool) -> ClaudeAccountSlot {
        ClaudeAccountSlot(
            slotID: slotID,
            accountKey: "account-\(slotID.rawValue)",
            displayName: "Claude \(slotID.rawValue)",
            lastSnapshot: makeSnapshot(label: "claude-\(slotID.rawValue)"),
            lastSeenAt: Date(timeIntervalSince1970: 1_000),
            isActive: isActive
        )
    }

    private func makeSnapshot(label: String) -> UsageSnapshot {
        UsageSnapshot(
            source: label,
            status: .ok,
            remaining: 10,
            used: 1,
            limit: 11,
            unit: "requests",
            updatedAt: Date(timeIntervalSince1970: 1_000),
            note: ""
        )
    }
}
