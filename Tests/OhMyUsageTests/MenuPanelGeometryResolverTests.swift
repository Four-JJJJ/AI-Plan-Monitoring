import XCTest
@testable import OhMyUsage

final class MenuPanelGeometryResolverTests: XCTestCase {
    func testFallbackStatusIconRectCentersIconVertically() {
        let rect = MenuPanelGeometryResolver.fallbackStatusIconRect(
            buttonBounds: CGRect(x: 0, y: 0, width: 24, height: 22),
            statusIconSize: 16
        )

        XCTAssertEqual(rect.origin.x, 0)
        XCTAssertEqual(rect.origin.y, 3)
        XCTAssertEqual(rect.size.width, 16)
        XCTAssertEqual(rect.size.height, 16)
    }

    func testAlignedPanelFrameCentersBelowIconWithoutVisibleBounds() {
        let frame = MenuPanelGeometryResolver.alignedPanelFrame(
            panelFrame: CGRect(x: 0, y: 0, width: 340, height: 120),
            iconRectOnScreen: CGRect(x: 500, y: 900, width: 16, height: 16),
            visibleFrame: nil,
            gapBelowStatusIcon: 1
        )

        XCTAssertEqual(frame.origin.x, 338)
        XCTAssertEqual(frame.origin.y, 779)
    }

    func testAlignedPanelFrameClampsWithinVisibleBounds() {
        let frame = MenuPanelGeometryResolver.alignedPanelFrame(
            panelFrame: CGRect(x: 0, y: 0, width: 340, height: 120),
            iconRectOnScreen: CGRect(x: 20, y: 40, width: 16, height: 16),
            visibleFrame: CGRect(x: 10, y: 10, width: 360, height: 240),
            gapBelowStatusIcon: 1
        )

        XCTAssertEqual(frame.origin.x, 10)
        XCTAssertEqual(frame.origin.y, 10)
    }

    func testHorizontalCenterRatioUsesScreenBounds() {
        let ratio = MenuPanelGeometryResolver.horizontalCenterRatio(
            rectOnScreen: CGRect(x: 450, y: 0, width: 20, height: 20),
            screenFrame: CGRect(x: 100, y: 0, width: 1000, height: 800)
        )

        XCTAssertEqual(ratio, 0.36, accuracy: 0.0001)
    }
}
