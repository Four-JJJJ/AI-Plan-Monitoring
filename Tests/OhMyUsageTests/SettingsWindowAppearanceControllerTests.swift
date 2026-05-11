import AppKit
import OhMyUsageApplication
import XCTest
@testable import OhMyUsage

@MainActor
final class SettingsWindowAppearanceControllerTests: XCTestCase {
    func testRefreshWallpaperLuminanceOnlySamplesInFollowWallpaperMode() {
        var sampledScreens: [NSScreen?] = []
        let controller = SettingsWindowAppearanceController(
            wallpaperLuminanceResolver: {
                sampledScreens.append($0)
                return 0.72
            },
            usesLightAppearanceResolver: { _, _ in false },
            applyWindowAppearance: { _, _ in }
        )

        XCTAssertNil(controller.refreshWallpaperLuminance(mode: .dark, screen: nil))
        XCTAssertEqual(sampledScreens.count, 0)

        XCTAssertEqual(
            controller.refreshWallpaperLuminance(mode: .followWallpaper, screen: nil) ?? -1,
            0.72,
            accuracy: 0.0001
        )
        XCTAssertEqual(sampledScreens.count, 1)
    }

    func testUsesLightAppearanceDelegatesToResolver() {
        let controller = SettingsWindowAppearanceController(
            wallpaperLuminanceResolver: { _ in nil },
            usesLightAppearanceResolver: { mode, luminance in
                mode == .followWallpaper && luminance == 0.9
            },
            applyWindowAppearance: { _, _ in }
        )

        XCTAssertTrue(
            controller.usesLightAppearance(
                mode: .followWallpaper,
                wallpaperLuminance: 0.9
            )
        )
        XCTAssertFalse(
            controller.usesLightAppearance(
                mode: .dark,
                wallpaperLuminance: 0.9
            )
        )
    }

    func testApplyWindowAppearanceUsesResolvedForegroundStyle() {
        let window = NSWindow()
        var applied: [(NSWindow, Bool)] = []
        let controller = SettingsWindowAppearanceController(
            wallpaperLuminanceResolver: { _ in nil },
            usesLightAppearanceResolver: { mode, luminance in
                mode == .light || luminance == 0.8
            },
            applyWindowAppearance: { applied.append(($0, $1)) }
        )

        controller.applyWindowAppearance(
            mode: .followWallpaper,
            wallpaperLuminance: 0.8,
            window: window
        )

        XCTAssertEqual(applied.count, 1)
        XCTAssertTrue(applied[0].0 === window)
        XCTAssertTrue(applied[0].1)
    }
}
