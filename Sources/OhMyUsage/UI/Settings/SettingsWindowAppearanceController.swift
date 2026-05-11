import AppKit
import OhMyUsageApplication

@MainActor
final class SettingsWindowAppearanceController {
    private let wallpaperLuminanceResolver: (NSScreen?) -> Double?
    private let usesLightAppearanceResolver: (StatusBarAppearanceMode, Double?) -> Bool
    private let applyWindowAppearance: (NSWindow, Bool) -> Void

    init(
        wallpaperLuminanceResolver: @escaping (NSScreen?) -> Double? = {
            SettingsWindowAppearanceResolver.wallpaperLuminance(for: $0)
        },
        usesLightAppearanceResolver: @escaping (StatusBarAppearanceMode, Double?) -> Bool = {
            SettingsWindowAppearanceResolver.usesLightAppearance(
                mode: $0,
                wallpaperLuminance: $1
            )
        },
        applyWindowAppearance: @escaping (NSWindow, Bool) -> Void = {
            SettingsWindowAppearanceResolver.apply(to: $0, usesLightAppearance: $1)
        }
    ) {
        self.wallpaperLuminanceResolver = wallpaperLuminanceResolver
        self.usesLightAppearanceResolver = usesLightAppearanceResolver
        self.applyWindowAppearance = applyWindowAppearance
    }

    func usesLightAppearance(
        mode: StatusBarAppearanceMode,
        wallpaperLuminance: Double?
    ) -> Bool {
        usesLightAppearanceResolver(mode, wallpaperLuminance)
    }

    func refreshWallpaperLuminance(
        mode: StatusBarAppearanceMode,
        screen: NSScreen?
    ) -> Double? {
        guard mode == .followWallpaper else {
            return nil
        }
        return wallpaperLuminanceResolver(screen)
    }

    func applyWindowAppearance(
        mode: StatusBarAppearanceMode,
        wallpaperLuminance: Double?,
        window: NSWindow?
    ) {
        guard let window else { return }
        let usesLightAppearance = usesLightAppearance(
            mode: mode,
            wallpaperLuminance: wallpaperLuminance
        )
        applyWindowAppearance(window, usesLightAppearance)
    }
}
