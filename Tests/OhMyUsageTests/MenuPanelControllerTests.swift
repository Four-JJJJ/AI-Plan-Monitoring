import AppKit
import XCTest
@testable import OhMyUsage

@MainActor
final class MenuPanelControllerTests: XCTestCase {
    func testShouldCloseForOutsideClickWhenShownAndOutsideFrames() {
        let shouldClose = MenuPanelController.shouldCloseForOutsideClick(
            isShown: true,
            isProtectedForegroundApp: false,
            mouseLocation: NSPoint(x: 400, y: 400),
            panelFrame: NSRect(x: 0, y: 0, width: 100, height: 100),
            statusItemFrame: NSRect(x: 120, y: 0, width: 40, height: 20)
        )

        XCTAssertTrue(shouldClose)
    }

    func testShouldNotCloseForProtectedForegroundApp() {
        let shouldClose = MenuPanelController.shouldCloseForOutsideClick(
            isShown: true,
            isProtectedForegroundApp: true,
            mouseLocation: NSPoint(x: 400, y: 400),
            panelFrame: NSRect(x: 0, y: 0, width: 100, height: 100),
            statusItemFrame: NSRect(x: 120, y: 0, width: 40, height: 20)
        )

        XCTAssertFalse(shouldClose)
    }

    func testProtectedOutsideClickBundleIDMatchesKnownAppsAndSecurityAgentFragments() {
        let protectedBundleIDs: Set<String> = [
            "com.apple.securityagent",
            "com.apple.systemsettings",
            "com.apple.systempreferences",
            "com.apple.preference.security.remoteservice"
        ]

        XCTAssertTrue(
            MenuPanelController.isProtectedOutsideClickBundleID(
                "com.apple.systemsettings",
                protectedOutsideClickBundleIDs: protectedBundleIDs
            )
        )
        XCTAssertTrue(
            MenuPanelController.isProtectedOutsideClickBundleID(
                "com.apple.preference.security.remoteservice",
                protectedOutsideClickBundleIDs: protectedBundleIDs
            )
        )
        XCTAssertFalse(
            MenuPanelController.isProtectedOutsideClickBundleID(
                "com.example.other",
                protectedOutsideClickBundleIDs: protectedBundleIDs
            )
        )
    }
}
