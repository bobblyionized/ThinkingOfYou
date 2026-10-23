//  Theme.swift
//  ThinkingOfYou/UI — design tokens: color, type, spacing, shape, motion.
//
//  Direction: "night letter". The app is always dark (the root forces the
//  dark color scheme): charcoal pages, warm off-white ink, and a deep pink
//  accent, matching the dark-gray-and-pink heart icon. Headings use the
//  serif system face (New York) like the opening line of a letter; numbers
//  use SF Rounded with tabular digits so countdowns never jitter.

import SwiftUI
import UIKit

// MARK: - Color

enum Theme {
    /// Page background: near-black charcoal.
    static let paper = Color(hex: 0x121012)
    /// Raised surfaces: cards, rows, the top bar.
    static let card = Color(hex: 0x1D1A1D)
    /// Deep pink tint for fills behind icons and avatars.
    static let blush = Color(hex: 0x3A1626)
    /// Main text.
    static let ink = Color(hex: 0xF1E4E9)
    /// Secondary text.
    static let inkSoft = Color(hex: 0xA3929A)
    /// Brand deep pink (matches AccentColor). Use for shapes, not small text.
    static let rose = Color(hex: 0xC2185B)
    /// Deep pink that is legible as text on `paper` / `card`.
    static let wine = Color(hex: 0xE04E86)
    /// Deep pink fill for primary buttons (paired with `onRose`).
    static let roseFill = Color(hex: 0xAD1457)
    /// Text and icons on `roseFill`.
    static let onRose = Color(hex: 0xFFFFFF)
    /// Hairlines and outlines.
    static let hairline = Color(hex: 0x2E272B)
    /// Background of the toast capsule.
    static let toastFill = Color(hex: 0x2A2328)
    /// Text on `toastFill`.
    static let onToast = Color(hex: 0xF1E4E9)
}

// MARK: - Spacing / shape

enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

enum Radius {
    /// Small chips and fields.
    static let small: CGFloat = 12
    /// Cards and notices.
    static let card: CGFloat = 22
    /// Sheets' inner panels.
    static let large: CGFloat = 28
}

// MARK: - Type

extension Font {
    /// Letter-heading serif. Scales with Dynamic Type.
    static func toyDisplay(_ style: Font.TextStyle = .largeTitle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    /// Rounded, tabular numbers for times and counts.
    static func toyNumber(_ style: Font.TextStyle = .body, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight).monospacedDigit()
    }

    /// Rounded UI label (pills, chips, buttons).
    static func toyLabel(_ style: Font.TextStyle = .subheadline, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

// MARK: - Motion

enum Motion {
    /// The house spring: soft, slightly buoyant.
    static let spring = Animation.spring(duration: 0.42, bounce: 0.22)
    /// Quicker spring for small state changes.
    static let snap = Animation.spring(duration: 0.28, bounce: 0.15)

    /// The house spring, or a short fade when Reduce Motion is on.
    static func gentle(reduced: Bool) -> Animation {
        reduced ? Animation.easeInOut(duration: 0.18) : Motion.spring
    }

    /// The quick spring, or a short fade when Reduce Motion is on.
    static func quick(reduced: Bool) -> Animation {
        reduced ? Animation.easeInOut(duration: 0.15) : Motion.snap
    }
}

// MARK: - Helpers

extension Color {
    /// A fixed color. Hex is 0xRRGGBB.
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// A color that follows the light/dark appearance. Hex is 0xRRGGBB.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
