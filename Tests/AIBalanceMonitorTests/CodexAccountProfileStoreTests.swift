import Foundation
import XCTest
@testable import AIBalanceMonitor

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

    func testRemoveProfileKeepsCurrentSystemAccount() throws {
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

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.slotID, .a)
        XCTAssertTrue(profiles.first?.isCurrentSystemAccount == true)
    }

    private func makeStore() -> CodexAccountProfileStore {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-profile-tests-\(UUID().uuidString).json")
        return CodexAccountProfileStore(fileURL: path)
    }

    private func sampleAuthJSON(accountID: String, email: String, accessToken: String? = nil) -> String {
        let payload = Data(#"{"email":"\#(email)"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return #"""
        {
          "tokens": {
            "access_token": "\#(accessToken ?? "access-token-\(accountID)")",
            "refresh_token": "refresh-token-\#(accountID)",
            "account_id": "\#(accountID)",
            "id_token": "header.\#(payload).signature"
          }
        }
        """#
    }
}
