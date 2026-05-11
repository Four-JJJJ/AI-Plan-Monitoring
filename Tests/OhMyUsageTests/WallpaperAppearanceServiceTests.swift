import AppKit
import XCTest
@testable import OhMyUsage

final class WallpaperAppearanceServiceTests: XCTestCase {
    func testFollowWallpaperUsesFallbackStyleWhenProbeCannotResolveLuminance() {
        let service = WallpaperAppearanceService(
            imageLoader: { _ in nil },
            luminanceResolver: { _, _ in nil }
        )
        let probe = WallpaperAppearanceProbe(
            screenID: "main",
            wallpaperURL: URL(fileURLWithPath: "/tmp/missing.png"),
            horizontalCenterRatio: 0.5
        )

        let style = service.resolvedForegroundStyle(
            mode: .followWallpaper,
            probe: probe,
            fallbackStyle: .dark
        )

        XCTAssertEqual(style, .dark)
    }

    func testManualModeDoesNotLoadWallpaperProbe() {
        var loadCount = 0
        let service = WallpaperAppearanceService(
            imageLoader: { _ in
                loadCount += 1
                return NSImage(size: NSSize(width: 1, height: 1))
            },
            luminanceResolver: { _, _ in 0.9 }
        )
        let probe = WallpaperAppearanceProbe(
            screenID: "main",
            wallpaperURL: URL(fileURLWithPath: "/tmp/wallpaper.png"),
            horizontalCenterRatio: 0.5
        )

        let style = service.resolvedForegroundStyle(
            mode: .dark,
            probe: probe,
            fallbackStyle: .light
        )

        XCTAssertEqual(style, .light)
        XCTAssertEqual(loadCount, 0)
    }

    func testCacheAvoidsReloadingSameWallpaperProbe() {
        var loadCount = 0
        let service = WallpaperAppearanceService(
            imageLoader: { _ in
                loadCount += 1
                return NSImage(size: NSSize(width: 1, height: 1))
            },
            luminanceResolver: { _, _ in 0.85 }
        )
        let probe = WallpaperAppearanceProbe(
            screenID: "screen-1",
            wallpaperURL: URL(fileURLWithPath: "/tmp/wallpaper.png"),
            horizontalCenterRatio: 0.42
        )

        let first = service.resolvedForegroundStyle(
            mode: .followWallpaper,
            probe: probe,
            fallbackStyle: nil
        )
        let second = service.resolvedForegroundStyle(
            mode: .followWallpaper,
            probe: probe,
            fallbackStyle: nil
        )

        XCTAssertEqual(first, .dark)
        XCTAssertEqual(second, .dark)
        XCTAssertEqual(loadCount, 1)
    }

    func testClearCacheForcesWallpaperProbeReload() {
        var loadCount = 0
        let service = WallpaperAppearanceService(
            imageLoader: { _ in
                loadCount += 1
                return NSImage(size: NSSize(width: 1, height: 1))
            },
            luminanceResolver: { _, _ in 0.2 }
        )
        let probe = WallpaperAppearanceProbe(
            screenID: "screen-1",
            wallpaperURL: URL(fileURLWithPath: "/tmp/wallpaper.png"),
            horizontalCenterRatio: 0.42
        )

        _ = service.resolvedForegroundStyle(
            mode: .followWallpaper,
            probe: probe,
            fallbackStyle: nil
        )
        service.clearCache()
        _ = service.resolvedForegroundStyle(
            mode: .followWallpaper,
            probe: probe,
            fallbackStyle: nil
        )

        XCTAssertEqual(loadCount, 2)
    }
}
