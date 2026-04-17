import Foundation
import XCTest
@testable import AIPlanMonitor

final class CodexAccountProfileStoreTests: XCTestCase {
    func testSaveProfileParsesCodexMetadata() throws {
        let store = makeStore()
        let profile = try store.saveProfile(
            slotID: .a,
            displayName: "Main",
            authJSON: sampleAuthJSON(accountID: "acc-1", email: "user@example.com"),
            currentFingerprint: nil
        )

        XCTAssertEqual(profile.displayName, "Main")
        XCTAssertEqual(profile.accountId, "acc-1")
        XCTAssertEqual(profile.accountEmail, "user@example.com")
        XCTAssertEqual(profile.accountSubject, "sub-acc-1")
        XCTAssertEqual(profile.tenantKey, "account:acc-1")
        XCTAssertEqual(profile.identityKey, "tenant:account:acc-1|principal:subject:sub-acc-1")
        XCTAssertNotNil(profile.credentialFingerprint)
    }

    func testSaveProfileRejectsMissingAccessToken() {
        let store = makeStore()
        XCTAssertThrowsError(
            try store.saveProfile(
                slotID: .a,
                displayName: "Broken",
                authJSON: #"{"tokens":{"refresh_token":"x"}}"#,
                currentFingerprint: nil
            )
        )
    }

    func testNextAvailableSlotIDAdvancesPastImportedProfiles() throws {
        let store = makeStore()
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "A",
            authJSON: sampleAuthJSON(accountID: "acc-1", email: "a@example.com"),
            currentFingerprint: nil
        )
        _ = try store.saveProfile(
            slotID: CodexSlotID(rawValue: "C"),
            displayName: "C",
            authJSON: sampleAuthJSON(accountID: "acc-3", email: "c@example.com"),
            currentFingerprint: nil
        )

        XCTAssertEqual(store.nextAvailableSlotID().rawValue, "B")
    }

    func testCaptureCurrentAuthStoresIntoFirstAvailableAutoSlot() {
        let store = makeStore()

        let profiles = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-a", email: "auto-a@example.com")
        )

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.slotID, .a)
        XCTAssertEqual(profiles.first?.displayName, "Codex A")
        XCTAssertTrue(profiles.first?.isCurrentSystemAccount == true)
    }

    func testCaptureCurrentAuthStoresSecondDistinctAccountIntoSlotB() {
        let store = makeStore()

        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-a", email: "auto-a@example.com")
        )
        let profiles = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-b", email: "auto-b@example.com")
        )

        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles.map(\.slotID), [.a, .b])
        XCTAssertEqual(profiles.first(where: { $0.slotID == .b })?.displayName, "Codex B")
        XCTAssertTrue(profiles.first(where: { $0.slotID == .b })?.isCurrentSystemAccount == true)
        XCTAssertFalse(profiles.first(where: { $0.slotID == .a })?.isCurrentSystemAccount == true)
    }

    func testCaptureCurrentAuthKeepsSameEmailDifferentTeamsAsSeparateProfiles() {
        let store = makeStore()
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "team-a",
                email: "shared@example.com",
                subject: "sub-shared"
            )
        )
        let profiles = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "team-b",
                email: "shared@example.com",
                subject: "sub-shared"
            )
        )

        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(Set(profiles.compactMap(\.accountId)), ["team-a", "team-b"])
    }

    func testCaptureCurrentAuthStoresThirdDistinctAccountIntoSlotC() {
        let store = makeStore()

        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-a", email: "auto-a@example.com")
        )
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-b", email: "auto-b@example.com")
        )
        let profiles = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-c", email: "auto-c@example.com")
        )

        XCTAssertEqual(profiles.count, 3)
        XCTAssertEqual(profiles.map(\.slotID.rawValue), ["A", "B", "C"])
        XCTAssertEqual(profiles.first(where: { $0.slotID.rawValue == "C" })?.displayName, "Codex C")
    }

    func testCaptureCurrentAuthUpdatesMatchingSlotWithoutCreatingNewOne() {
        let store = makeStore()
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-a", email: "auto-a@example.com")
        )

        let profiles = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "acc-auto-a",
                email: "auto-a@example.com",
                accessToken: "rotated-access-token"
            )
        )

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.slotID, .a)
        XCTAssertTrue(profiles.first?.authJSON.contains("rotated-access-token") == true)
    }

    func testCaptureCurrentAuthDoesNotMergeDifferentTeamsEvenWhenFingerprintMatches() {
        let store = makeStore()
        let sharedToken = "same-access-token"
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "team-a",
                email: "shared@example.com",
                subject: "sub-shared",
                accessToken: sharedToken
            )
        )
        let profiles = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "team-b",
                email: "shared@example.com",
                subject: "sub-shared",
                accessToken: sharedToken
            )
        )

        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(Set(profiles.compactMap(\.accountId)), ["team-a", "team-b"])
    }

    func testCurrentSystemAccountUsesIdentityWhenFingerprintIsSharedAcrossTeams() {
        let store = makeStore()
        let sharedToken = "same-access-token"
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "team-a",
                email: "shared@example.com",
                subject: "sub-shared",
                accessToken: sharedToken
            )
        )
        let profiles = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "team-b",
                email: "shared@example.com",
                subject: "sub-shared",
                accessToken: sharedToken
            )
        )

        XCTAssertEqual(profiles.filter(\.isCurrentSystemAccount).count, 1)
        XCTAssertEqual(profiles.first(where: \.isCurrentSystemAccount)?.accountId, "team-b")
    }

    func testSnapshotMatchingPrefersTeamScopedIdentityOverFingerprintFallback() {
        let store = makeStore()
        let sharedToken = "same-access-token"
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "team-a",
                email: "shared@example.com",
                subject: "sub-shared",
                accessToken: sharedToken
            )
        )
        let profiles = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "team-b",
                email: "shared@example.com",
                subject: "sub-shared",
                accessToken: sharedToken
            )
        )
        let snapshot = makeSnapshot(
            accountID: "team-b",
            accountLabel: "shared@example.com",
            subject: "sub-shared",
            fingerprint: try? CodexAccountProfileStore.parseAuthJSON(
                sampleAuthJSON(accountID: "team-a", email: "shared@example.com", subject: "sub-shared", accessToken: sharedToken)
            ).credentialFingerprint
        )

        guard let index = CodexAccountProfileStore.matchingIndex(for: snapshot, in: profiles) else {
            return XCTFail("expected snapshot to match a profile")
        }

        XCTAssertEqual(profiles[index].accountId, "team-b")
    }

    func testRemoveProfileDeletesSlot() {
        let store = makeStore()
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-a", email: "auto-a@example.com")
        )
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-b", email: "auto-b@example.com")
        )

        let profiles = store.removeProfile(slotID: .a)

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.slotID, .b)
    }

    func testRemoveProfileCanDeleteCurrentSystemAccount() throws {
        let store = makeStore()
        let authJSON = sampleAuthJSON(accountID: "acc-current", email: "current@example.com")
        let fingerprint = try CodexAccountProfileStore.parseAuthJSON(authJSON).credentialFingerprint
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Current",
            authJSON: authJSON,
            currentFingerprint: fingerprint
        )

        let profiles = store.removeProfile(slotID: .a)

        XCTAssertTrue(profiles.isEmpty)
    }

    func testExplicitSaveMovesMatchingAccountIntoChosenSlotWithoutOverwritingOthers() throws {
        let store = makeStore()
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Codex A",
            authJSON: sampleAuthJSON(accountID: "acc-a", email: "a@example.com"),
            currentFingerprint: nil
        )
        _ = try store.saveProfile(
            slotID: .b,
            displayName: "Codex B",
            authJSON: sampleAuthJSON(accountID: "acc-b", email: "b@example.com"),
            currentFingerprint: nil
        )

        _ = try store.saveProfile(
            slotID: CodexSlotID(rawValue: "C"),
            displayName: "Codex C",
            authJSON: sampleAuthJSON(accountID: "acc-a", email: "a@example.com", accessToken: "rotated-a"),
            currentFingerprint: nil
        )

        let profiles = store.profiles()
        XCTAssertEqual(profiles.map(\.slotID.rawValue), ["B", "C"])
        XCTAssertEqual(profiles.first(where: { $0.slotID.rawValue == "C" })?.accountId, "acc-a")
        XCTAssertEqual(profiles.first(where: { $0.slotID == .b })?.accountId, "acc-b")
    }

    func testRemovedCurrentFingerprintIsNotAutoCapturedAgainImmediately() throws {
        let store = makeStore()
        let authJSON = sampleAuthJSON(accountID: "acc-current", email: "current@example.com")
        let fingerprint = try CodexAccountProfileStore.parseAuthJSON(authJSON).credentialFingerprint
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Current",
            authJSON: authJSON,
            currentFingerprint: fingerprint
        )

        _ = store.removeProfile(slotID: .a)
        let profiles = store.captureCurrentAuthIfNeeded(authJSON: authJSON)

        XCTAssertTrue(profiles.isEmpty)
    }

    private func makeStore() -> CodexAccountProfileStore {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-profile-tests-\(UUID().uuidString).json")
        return CodexAccountProfileStore(fileURL: path)
    }

    private func sampleAuthJSON(
        accountID: String?,
        email: String,
        subject: String? = nil,
        accessToken: String? = nil
    ) -> String {
        let subjectValue = subject ?? "sub-\(accountID ?? "default")"
        let payload = Data(#"{"email":"\#(email)","sub":"\#(subjectValue)"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let accountLine: String
        if let accountID {
            accountLine = #"""
            "account_id": "\#(accountID)",
            """#
        } else {
            accountLine = ""
        }
        let accountSuffix = accountID ?? "default"
        return #"""
        {
          "tokens": {
            "access_token": "\#(accessToken ?? "access-token-\(accountSuffix)")",
            "refresh_token": "refresh-token-\#(accountSuffix)",
            \#(accountLine)
            "id_token": "header.\#(payload).signature"
          }
        }
        """#
    }

    private func makeSnapshot(
        accountID: String?,
        accountLabel: String?,
        subject: String?,
        fingerprint: String?
    ) -> UsageSnapshot {
        var rawMeta: [String: String] = [:]
        if let accountID {
            rawMeta["codex.accountId"] = accountID
            rawMeta["codex.teamId"] = accountID
        }
        if let accountLabel {
            rawMeta["codex.accountLabel"] = accountLabel
        }
        if let subject {
            rawMeta["codex.subject"] = subject
        }
        if let fingerprint {
            rawMeta["codex.credentialFingerprint"] = fingerprint
        }

        return UsageSnapshot(
            source: "codex-official",
            status: .ok,
            remaining: 50,
            used: 50,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "",
            quotaWindows: [],
            sourceLabel: "API",
            accountLabel: accountLabel,
            extras: [:],
            rawMeta: rawMeta
        )
    }
}
