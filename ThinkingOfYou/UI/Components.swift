//  Components.swift
//  ThinkingOfYou/UI — shared building blocks: the heart shape and the
//  draining heart (the app's one signature element), avatars, button
//  styles, notice cards and toasts.

import SwiftUI
import UIKit

// MARK: - Heart

/// A plump, slightly letterpress heart that fills its rect.
struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: p(0.5, 0.97))
        path.addCurve(to: p(0.0, 0.33), control1: p(0.32, 0.80), control2: p(0.0, 0.60))
        path.addCurve(to: p(0.25, 0.03), control1: p(0.0, 0.15), control2: p(0.12, 0.03))
        path.addCurve(to: p(0.5, 0.20), control1: p(0.38, 0.03), control2: p(0.47, 0.12))
        path.addCurve(to: p(0.75, 0.03), control1: p(0.53, 0.12), control2: p(0.62, 0.03))
        path.addCurve(to: p(1.0, 0.33), control1: p(0.88, 0.03), control2: p(1.0, 0.15))
        path.addCurve(to: p(0.5, 0.97), control1: p(1.0, 0.60), control2: p(0.68, 0.80))
        path.closeSubpath()
        return path
    }
}

/// A heart that empties from the top like an hourglass as time is spent.
/// `fraction` is 0...1 of time left.
struct DrainingHeart: View {
    var fraction: Double
    var fill: Color = Theme.rose
    var empty: Color = Theme.blush
    var lineWidth: CGFloat = 0

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        ZStack {
            HeartShape().fill(empty)
            HeartShape()
                .fill(fill)
                .mask {
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Rectangle().frame(height: geo.size.height * clamped)
                        }
                    }
                }
            if lineWidth > 0 {
                HeartShape().stroke(fill, lineWidth: lineWidth)
            }
        }
        .aspectRatio(1.08, contentMode: .fit)
        .animation(.easeOut(duration: 0.6), value: clamped)
        .accessibilityHidden(true)
    }
}

// MARK: - Avatar

struct AvatarView: View {
    let person: Person
    var size: CGFloat = 44
    /// Draws a rose ring (used for pinned people).
    var ringed: Bool = false

    var body: some View {
        ZStack {
            if let data = person.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.blush
                Text(person.initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.wine)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .padding(ringed ? 3 : 0)
        .overlay {
            if ringed {
                Circle().strokeBorder(Theme.rose, lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Button styles

/// The one primary action on a screen: a rose capsule, full width.
struct RoseButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.toyLabel(.body))
            .foregroundStyle(Theme.onRose)
            .padding(.vertical, Space.m + 2)
            .padding(.horizontal, Space.xl)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Theme.roseFill))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.snap, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Secondary action: blush capsule with wine text.
struct SoftButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.toyLabel(.subheadline))
            .foregroundStyle(Theme.wine)
            .padding(.vertical, Space.s + 2)
            .padding(.horizontal, Space.l)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(Capsule().fill(Theme.blush))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.snap, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Round icon button used for Message / Call / FaceTime.
struct CircleIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var diameter: CGFloat = 38

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.40, weight: .semibold))
            .foregroundStyle(Theme.wine)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(Theme.blush))
            .opacity(isEnabled ? 1 : 0.3)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.snap, value: configuration.isPressed)
            .contentShape(Circle())
    }
}

extension ButtonStyle where Self == RoseButtonStyle {
    static var rose: RoseButtonStyle { RoseButtonStyle() }
}

extension ButtonStyle where Self == SoftButtonStyle {
    static var soft: SoftButtonStyle { SoftButtonStyle() }
    static var softWide: SoftButtonStyle { SoftButtonStyle(fullWidth: true) }
}

extension ButtonStyle where Self == CircleIconButtonStyle {
    static var circleIcon: CircleIconButtonStyle { CircleIconButtonStyle() }
}

// MARK: - Notice card

/// An explainer or empty/error state with one optional action.
struct NoticeCard: View {
    let systemImage: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Theme.wine)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.blush))
                .accessibilityHidden(true)
            Text(title)
                .font(.toyDisplay(.title3))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.rose)
                    .padding(.top, Space.xs)
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Toast

/// A small dark capsule that floats over content.
struct ToastCapsule: View {
    let text: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: Space.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.rose)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.toyLabel(.subheadline, weight: .medium))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.onToast)
        .padding(.vertical, Space.m)
        .padding(.horizontal, Space.l + 2)
        .background(Capsule().fill(Theme.toastFill))
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 6)
        .padding(.horizontal, Space.xl)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Section heading

/// Serif heading used above list groups (sentence case, never all caps).
struct SectionHeading: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.toyDisplay(.headline))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: Space.s)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
    }
}
