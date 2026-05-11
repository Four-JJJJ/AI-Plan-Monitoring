import XCTest
@testable import OhMyUsage

final class OfficialProfileNamingTests: XCTestCase {
    func testLimitedNoteTrimsAndCapsAtEightCharacters() {
        XCTAssertEqual(OfficialProfileNaming.limitedNote("  工作账号123456  "), "工作账号1234")
        XCTAssertEqual(OfficialProfileNaming.limitedNote(" personal "), "personal")
        XCTAssertEqual(OfficialProfileNaming.limitedNote(""), "")
    }

    func testDisplayNameAppendsNoteAfterModelNameWithSingleSpace() {
        XCTAssertEqual(
            OfficialProfileNaming.displayName(modelName: "Codex", slotID: .a, note: "工作"),
            "Codex 工作"
        )
        XCTAssertEqual(
            OfficialProfileNaming.displayName(modelName: "Claude", slotID: .b, note: "个人账号123456"),
            "Claude 个人账号1234"
        )
    }

    func testDisplayNameKeepsSlotFallbackWithoutNote() {
        XCTAssertEqual(
            OfficialProfileNaming.displayName(modelName: "Codex", slotID: CodexSlotID(rawValue: "C"), note: " \n "),
            "Codex C"
        )
    }
}
