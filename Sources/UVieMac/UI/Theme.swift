import SwiftUI
import AppKit

// MARK: - Design Tokens

enum UVieTheme {
    /// Brand vermilion from the app icon. Used for fills (white text on it)
    /// and as the `.tint`.
    static let accent = Color(red: 0xCF / 255, green: 0x3F / 255, blue: 0x2A / 255)

    /// Accent used as a FOREGROUND on the window background (icons,
    /// link-like buttons, status text): darker in light, lighter in dark.
    static let accentText = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(red: 0xFF / 255, green: 0x7A / 255, blue: 0x63 / 255, alpha: 1)
            : NSColor(red: 0xC2 / 255, green: 0x3A / 255, blue: 0x26 / 255, alpha: 1)
    })

    /// Selected/active backgrounds.
    static let accentSoft = accent.opacity(0.13)

    static let cardRadius: CGFloat = 10
    static let controlRadius: CGFloat = 7
    static let keycapRadius: CGFloat = 5
    static let hairline = Color.primary.opacity(0.08)
}
