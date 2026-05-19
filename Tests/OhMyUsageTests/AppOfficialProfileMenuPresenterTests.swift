import OhMyUsageDomain
import Foundation
import XCTest
@testable import OhMyUsage

final class AppOfficialProfileMenuPresenterTests: XCTestCase {
    func testCodexSlotViewModelsPreferCurrentProfileAndExposeFeedback() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let profiles = [
            makeCodexProfile(slotID: .a, email: "a@example.com", importedAt: now, isCurrent: false),
            makeCodexProfile(slotID: .b, email: "b@example.com", importedAt: now.addingTimeInterval(60), isCurrent: true)
        ]
        let slots = [
            makeCodexSlot(slotID: .a, email: "a@example.com", lastSeenAt: now.addingTimeInterval(10), isActive: true),
            makeCodexSlot(slotID: .b, email: "b@example.com", lastSeenAt: now.addingTimeInterval(20), isActive: false)
        ]

        let models = AppOfficialProfileMenuPresenter.codexSlotViewModels(
            profiles: profiles,
            slots: slots,
            feedbackBySlotID: [.a: CodexSwitchFeedback(message: "Needs attention", isError: true)],
            isSwitching: { $0 == .a },
            titleForSlotID: { "Codex \($0.rawValue)" },
            now: now
        )

        XCTAssertEqual(models.map(\.slotID), [.b, .a])
        XCTAssertTrue(models[0].isActive)
        XCTAssertEqual(models[0].displayName, "Codex B")
        XCTAssertEqual(models[1].switchMessage, "Needs attention")
        XCTAssertTrue(models[1].switchMessageIsError)
        XCTAssertTrue(models[1].isSwitching)
        XCTAssertTrue(models[1].canSwitch)
    }

    func testCodexSlotViewModelsHideRuntimeSlotsWithoutImportedProfile() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let profiles = [
            makeCodexProfile(slotID: .a, email: "a@example.com", importedAt: now, isCurrent: false),
            makeCodexProfile(slotID: .b, email: "b@example.com", importedAt: now.addingTimeInterval(60), isCurrent: false)
        ]
        let deletedSlotID = CodexSlotID(rawValue: "C")
        let slots = [
            makeCodexSlot(slotID: .a, email: "a@example.com", lastSeenAt: now.addingTimeInterval(10), isActive: false),
            makeCodexSlot(slotID: .b, email: "b@example.com", lastSeenAt: now.addingTimeInterval(20), isActive: false),
            makeCodexSlot(slotID: deletedSlotID, email: "deleted@example.com", lastSeenAt: now.addingTimeInterval(120), isActive: true)
        ]

        let models = AppOfficialProfileMenuPresenter.codexSlotViewModels(
            profiles: profiles,
            slots: slots,
            feedbackBySlotID: [:],
            isSwitching: { _ in false },
            titleForSlotID: { "Codex \($0.rawValue)" },
            now: now
        )

        XCTAssertEqual(models.map(\.slotID), [.b, .a])
        XCTAssertFalse(models.contains(where: { $0.slotID == deletedSlotID }))
    }

    func testClaudeSlotViewModelsFilterInferenceOnlyProfilesAndSortActiveFirst() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let visible = makeClaudeProfile(
            slotID: .b,
            email: "visible@example.com",
            scopes: ["user:profile"],
            importedAt: now.addingTimeInterval(60),
            isCurrent: false
        )
        let hidden = makeClaudeProfile(
            slotID: .a,
            email: "hidden@example.com",
            scopes: ["user:inference"],
            importedAt: now,
            isCurrent: true
        )
        let slots = [
            makeClaudeSlot(slotID: .a, email: "hidden@example.com", lastSeenAt: now.addingTimeInterval(20), isActive: true),
            makeClaudeSlot(slotID: .b, email: "visible@example.com", lastSeenAt: now.addingTimeInterval(10), isActive: false)
        ]

        let models = AppOfficialProfileMenuPresenter.claudeSlotViewModels(
            profiles: [hidden, visible],
            slots: slots,
            feedbackBySlotID: [.b: ClaudeSwitchFeedback(message: "Switched", isError: false)],
            isSwitching: { _ in false },
            titleForSlotID: { "Claude \($0.rawValue)" },
            now: now
        )

        XCTAssertEqual(models.map(\.slotID), [.b])
        XCTAssertEqual(models[0].displayName, "Claude B")
        XCTAssertEqual(models[0].switchMessage, "Switched")
        XCTAssertFalse(models[0].switchMessageIsError)
    }

    func testSlotViewModelTitlesAppendProfileNotesToModelName() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let codexProfile = makeCodexProfile(
            slotID: .a,
            email: "work@example.com",
            importedAt: now,
            isCurrent: true,
            displayName: "Codex A",
            note: "工作"
        )
        let codexSlot = makeCodexSlot(
            slotID: .a,
            email: "work@example.com",
            lastSeenAt: now,
            isActive: true
        )

        let codexModels = AppOfficialProfileMenuPresenter.codexSlotViewModels(
            profiles: [codexProfile],
            slots: [codexSlot],
            feedbackBySlotID: [:],
            isSwitching: { _ in false },
            titleForSlotID: { "Codex \($0.rawValue)" },
            now: now
        )

        XCTAssertEqual(codexModels.first?.title, "Codex 工作")

        let claudeProfile = makeClaudeProfile(
            slotID: .b,
            email: "team@example.com",
            scopes: ["user:profile"],
            importedAt: now,
            isCurrent: true,
            displayName: "Claude B",
            note: "团队"
        )
        let claudeSlot = makeClaudeSlot(
            slotID: .b,
            email: "team@example.com",
            lastSeenAt: now,
            isActive: true
        )

        let claudeModels = AppOfficialProfileMenuPresenter.claudeSlotViewModels(
            profiles: [claudeProfile],
            slots: [claudeSlot],
            feedbackBySlotID: [:],
            isSwitching: { _ in false },
            titleForSlotID: { "Claude \($0.rawValue)" },
            now: now
        )

        XCTAssertEqual(claudeModels.first?.title, "Claude 团队")
    }

    private func makeCodexProfile(
        slotID: CodexSlotID,
        email: String,
        importedAt: Date,
        isCurrent: Bool,
        displayName: String? = nil,
        note: String? = nil
    ) -> CodexAccountProfile {
        CodexAccountProfile(
            slotID: slotID,
            displayName: displayName ?? "Codex \(slotID.rawValue)",
            note: note ?? "note-\(slotID.rawValue)",
            authJSON: "{}",
            accountId: "team-\(slotID.rawValue.lowercased())",
            accountEmail: email,
            accountSubject: "subject-\(slotID.rawValue.lowercased())",
            tenantKey: "tenant",
            identityKey: "tenant|subject-\(slotID.rawValue.lowercased())",
            credentialFingerprint: "fp-\(slotID.rawValue.lowercased())",
            lastImportedAt: importedAt,
            isCurrentSystemAccount: isCurrent
        )
    }

    private func makeCodexSlot(
        slotID: CodexSlotID,
        email: String,
        lastSeenAt: Date,
        isActive: Bool
    ) -> CodexAccountSlot {
        CodexAccountSlot(
            slotID: slotID,
            accountKey: "email:\(email)",
            displayName: "Slot \(slotID.rawValue)",
            lastSnapshot: UsageSnapshot(
                source: "codex-official",
                status: .ok,
                remaining: 80,
                used: 20,
                limit: 100,
                unit: "%",
                updatedAt: lastSeenAt,
                note: "ok",
                sourceLabel: "Codex",
                accountLabel: email,
                rawMeta: [
                    "codex.slotID": slotID.rawValue,
                    "codex.accountLabel": email
                ]
            ),
            lastSeenAt: lastSeenAt,
            isActive: isActive
        )
    }

    private func makeClaudeProfile(
        slotID: CodexSlotID,
        email: String,
        scopes: [String],
        importedAt: Date,
        isCurrent: Bool,
        displayName: String? = nil,
        note: String? = nil
    ) -> ClaudeAccountProfile {
        let root: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": "token-\(slotID.rawValue.lowercased())",
                "refreshToken": "refresh-\(slotID.rawValue.lowercased())",
                "scopes": scopes
            ],
            "accountId": "account-\(slotID.rawValue.lowercased())",
            "email": email
        ]
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        return ClaudeAccountProfile(
            slotID: slotID,
            displayName: displayName ?? "Claude \(slotID.rawValue)",
            note: note,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: String(data: data, encoding: .utf8),
            accountId: "account-\(slotID.rawValue.lowercased())",
            accountEmail: email,
            credentialFingerprint: "fp-\(slotID.rawValue.lowercased())",
            lastImportedAt: importedAt,
            isCurrentSystemAccount: isCurrent
        )
    }

    private func makeClaudeSlot(
        slotID: CodexSlotID,
        email: String,
        lastSeenAt: Date,
        isActive: Bool
    ) -> ClaudeAccountSlot {
        ClaudeAccountSlot(
            slotID: slotID,
            accountKey: "email:\(email)",
            displayName: "Slot \(slotID.rawValue)",
            lastSnapshot: UsageSnapshot(
                source: "claude-official",
                status: .ok,
                remaining: 75,
                used: 25,
                limit: 100,
                unit: "%",
                updatedAt: lastSeenAt,
                note: "ok",
                sourceLabel: "Claude",
                accountLabel: email,
                rawMeta: [
                    "claude.slotID": slotID.rawValue,
                    "claude.accountLabel": email
                ]
            ),
            lastSeenAt: lastSeenAt,
            isActive: isActive
        )
    }
}
