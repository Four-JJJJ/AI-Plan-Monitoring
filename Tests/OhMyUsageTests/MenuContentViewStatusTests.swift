import XCTest
@testable import OhMyUsage

final class MenuContentViewStatusTests: XCTestCase {
    func testCachedAuthExpiredStatusTextUsesFailureLabel() {
        XCTAssertEqual(
            MenuContentView.cachedFetchHealthStatusText(.authExpired, language: .zhHans),
            "故障"
        )
        XCTAssertNotEqual(
            MenuContentView.cachedFetchHealthStatusText(.authExpired, language: .zhHans),
            "失联"
        )
    }

    func testCachedAuthExpiredStatusTextUsesEnglishFailureLabel() {
        XCTAssertEqual(
            MenuContentView.cachedFetchHealthStatusText(.authExpired, language: .en),
            "Failure"
        )
    }
}
