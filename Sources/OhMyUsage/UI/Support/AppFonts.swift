import AppKit
import CoreText
import SwiftUI

enum AppFonts {
    private static let numericFontName = "AnonymousPro-Bold"

    static func registerBundledFonts() {
        registerNumericFontIfNeeded()
    }

    static func numeric(size: CGFloat, fallbackWeight: Font.Weight = .semibold) -> Font {
        registerNumericFontIfNeeded()

        guard NSFont(name: numericFontName, size: size) != nil else {
            return .system(size: size, weight: fallbackWeight, design: .monospaced)
        }

        return .custom(numericFontName, size: size)
    }

    static func numericNSFont(size: CGFloat, fallbackWeight: NSFont.Weight = .semibold) -> NSFont {
        registerNumericFontIfNeeded()

        guard let font = NSFont(name: numericFontName, size: size) else {
            return .monospacedSystemFont(ofSize: size, weight: fallbackWeight)
        }

        return font
    }

    private static func registerNumericFontIfNeeded() {
        guard NSFont(name: numericFontName, size: 12) == nil else { return }
        guard let fontURL = Bundle.module.url(forResource: "AnonymousPro-Bold", withExtension: "ttf") else {
            return
        }

        var registrationError: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &registrationError)
        registrationError?.release()
    }
}
