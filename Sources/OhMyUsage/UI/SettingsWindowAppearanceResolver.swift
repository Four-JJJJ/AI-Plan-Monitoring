import AppKit

enum SettingsWindowAppearanceResolver {
    static func usesLightAppearance(
        mode: StatusBarAppearanceMode,
        wallpaperLuminance: Double?
    ) -> Bool {
        switch mode {
        case .dark:
            return false
        case .light:
            return true
        case .followWallpaper:
            guard let wallpaperLuminance else { return false }
            return wallpaperLuminance >= StatusBarAppearanceResolver.wallpaperLuminanceThreshold
        }
    }

    static func wallpaperLuminance(for screen: NSScreen?) -> Double? {
        guard
            let screen = screen ?? NSScreen.main,
            let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen),
            let image = NSImage(contentsOf: wallpaperURL)
        else {
            return nil
        }

        return StatusBarAppearanceResolver.wallpaperTopStripLuminance(from: image)
    }

    static func appearanceName(usesLightAppearance: Bool) -> NSAppearance.Name {
        usesLightAppearance ? .aqua : .darkAqua
    }

    static func backgroundColor(usesLightAppearance: Bool) -> NSColor {
        usesLightAppearance
            ? NSColor(red: 243.0 / 255.0, green: 244.0 / 255.0, blue: 246.0 / 255.0, alpha: 1)
            : NSColor(red: 35.0 / 255.0, green: 35.0 / 255.0, blue: 35.0 / 255.0, alpha: 1)
    }

    @MainActor
    static func apply(to window: NSWindow, usesLightAppearance: Bool) {
        window.appearance = NSAppearance(named: appearanceName(usesLightAppearance: usesLightAppearance))
        window.backgroundColor = backgroundColor(usesLightAppearance: usesLightAppearance)
    }
}
