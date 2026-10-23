//  Theme.swift
//  ThinkingOfYou/UI — design tokens: color, type, spacing, shape, motion.
//
//  Direction: "blush stationery". Pages are a faintly pink writing paper,
//  text is a plum-brown ink, the accent is the app's rose. Headings use the
//  serif system face (New York) like the opening line of a letter; numbers
//  use SF Rounded with tabular digits so countdowns never jitter.

import SwiftUI
import UIKit

// MARK: - Color

enum Theme {
    /// Page background: blush writing paper / plum night.
    static let paper = Color(light: 0xFBF4F2, dark: 0x1A1215)
    /// Raised surfaces: cards, rows, the top bar.
    static let card = Color(light: 0xFFFBFA, dark: 0x261B1F)
    /// Soft rose tint for fills behind icons and avatars.
    static let blush = Color(light: 0xF8E0E6, dark: 0x3A2329)
    /// Main text.
    static let ink = Color(light: 0x33222A, dark: 0xF5E8EB)
    /// Secondary text.
    static let inkSoft = Color(light: 0x7A6870, dark: 0xB9A2A9)
    /// Brand rose (matches AccentColor). Use for shapes, not small text.
    static let rose = Color(light: 0xF2668B, dark: 0xFF809E)
    /// Rose that is legible as text on `paper` / `card`.
    static let wine = Color(light: 0xB2345A, dark: 0xFF9DB4)
    /// Rose fill for primary buttons (paired with `onRose`).
    static let roseFill = Color(light: 0xD9476F, dark: 0xFF809E)
    /// Text and icons on `roseFill`.
    static let onRose = Color(light: 0xFFFFFF, dark: 0x3B0F1D)
    /// Hairlines and outlines.
    static let hairline = Color(light: 0xEBDADD, dark: 0x3D2C32)
    /// Background of the dark toast capsule.
    static let toastFill = Color(light: 0x33222A, dark: 0xF5E8EB)
    /// Text on `toastFill`.
    static let onToast = Color(light: 0xFBF4F2, dark: 0x1A1215)
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
