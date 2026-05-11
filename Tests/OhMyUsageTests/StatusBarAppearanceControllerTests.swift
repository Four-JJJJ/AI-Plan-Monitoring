import AppKit
import XCTest
@testable import OhMyUsage

@MainActor
final class StatusBarAppearanceControllerTests: XCTestCase {
    func testShouldRefreshAppearanceOnlyWhenFollowWallpaperAndStyleChanges() {
        XCTAssertTrue(
            StatusBarAppearanceController.shouldRefreshAppearance(
                mode: .followWallpaper,
                newStyle: .dark,
                lastRenderedStyle: .light
            )
        )
        XCTAssertFalse(
            StatusBarAppearanceController.shouldRefreshAppearance(
                mode: .followWallpaper,
                newStyle: .dark,
                lastRenderedStyle: .dark
            )
        )
        XCTAssertFalse(
            StatusBarAppearanceController.shouldRefreshAppearance(
                mode: .light,
                newStyle: .dark,
                lastRenderedStyle: .light
            )
        )
    }

    func testResolvedForegroundStyleDelegatesToWallpaperService() {
        let service = WallpaperAppearanceService(
            imageLoader: { _ in NSImage(size: NSSize(width: 1, height: 1)) },
            luminanceResolver: { _, _ in 0.9 }
        )
        let controller = StatusBarAppearanceController(
            wallpaperAppearanceService: service
        )
        let probe = WallpaperAppearanceProbe(
            screenID: "main",
            wallpaperURL: URL(fileURLWithPath: "/tmp/wallpaper.png"),
            horizontalCenterRatio: 0.5
        )

        let style = controller.resolvedForegroundStyle(
            mode: .followWallpaper,
            probe: probe,
            fallbackStyle: nil
        )

        XCTAssertEqual(style, .dark)
    }
}
