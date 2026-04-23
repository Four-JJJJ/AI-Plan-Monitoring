import XCTest
@testable import AIPlanMonitor

final class MenuContentViewStatusTests: XCTestCase {
    func testCachedAuthExpiredStatusTextDoesNotUseDisconnectedLabel() {
        XCTAssertEqual(
            MenuContentView.cachedFetchHealthStatusText(.authExpired, language: .zhHans),
            "认证失效(缓存)"
        )
        XCTAssertNotEqual(
            MenuContentView.cachedFetchHealthStatusText(.authExpired, language: .zhHans),
            "失联"
        )
    }

    func testCachedAuthExpiredStatusTextSupportsEnglish() {
        XCTAssertEqual(
            MenuContentView.cachedFetchHealthStatusText(.authExpired, language: .en),
            "Auth Expired (Cached)"
        )
    }
}
