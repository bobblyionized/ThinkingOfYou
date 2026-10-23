//  ModeSwitcherView.swift
//  ThinkingOfYou/UI — the two-segment Instagram / Messages pill, and the
//  edge-swipe strip that flips modes without touching the web view's own
//  gestures.

import SwiftUI

// MARK: - Pill

struct ModePill: View {
    let mode: AppMode
    var compact: Bool = false
    let onSelect: (AppMode) -> Void

    @Namespace private var selection

    var body: some View {
        HStack(spacing: Space.xxs) {
            ForEach(AppMode.allCases) { item in
                segment(item)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.card))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mode")
    }

    private func segment(_ item: AppMode) -> some View {
        let isSelected = item == mode
        return Button {
            onSelect(item)
        } label: {
            Group {
                if compact {
                    Image(systemName: ModePill.icon(for: item))
                        .font(.footnote.weight(.semibold))
                } else {
                    Text(item.title)
                        .font(.toyLabel(.subheadline))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(isSelected ? Theme.onRose : Theme.inkSoft)
            .padding(.horizontal, compact ? Space.m + 2 : Space.m + 1)
            .frame(minHeight: 32)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.roseFill)
                        .matchedGeometryEffect(id: "selected", in: selection)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected ? "" : "Switches to \(item.title)")
    }

    static func icon(for mode: AppMode) -> String {
        switch mode {
        case .instagram: return "camera"
        case .messages: return "message"
        }
    }
}

// MARK: - Edge swipe

/// A narrow vertical band on one screen edge. Dragging inward from it flips
/// the mode. It covers only the middle of the edge so Instagram's header
/// buttons and DM composer stay reachable, and it is invisible to VoiceOver
/// (the pill does the same job there).
struct EdgeSwipeStrip: View {
    /// Which edge the strip sits on.
    let edge: HorizontalEdge
    /// The mode a completed swipe goes to (shown in the peek badge).
    let target: AppMode
    let reduceMotion: Bool
    /// 0...1 while dragging, for the parent to nudge the content.
    @Binding var progress: CGFloat
    let onSwipe: () -> Void

    private static let stripWidth: CGFloat = 16
    private static let dragTravel: CGFloat = 90

    private var width: CGFloat { Self.stripWidth }
    private var travel: CGFloat { Self.dragTravel }

    var body: some View {
        GeometryReader { geo in
            let x = edge == .trailing ? geo.size.width - width / 2 : width / 2
            let y = geo.size.height * 0.46

            // Faint handle: the only always-visible hint.
            Capsule()
                .fill(Theme.rose.opacity(Double(0.28 + 0.5 * progress)))
                .frame(width: 3 + 2 * progress, height: 44)
                .position(x: edge == .trailing ? geo.size.width - 5 : 5, y: y)
                .allowsHitTesting(false)

            // Peek badge that slides in with the drag.
            Image(systemName: ModePill.icon(for: target))
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.onRose)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.roseFill))
                .scaleEffect(0.6 + 0.4 * progress)
                .opacity(Double(progress))
                .position(x: edge == .trailing
                              ? geo.size.width - 22 - 34 * progress
                              : 22 + 34 * progress,
                          y: y)
                .allowsHitTesting(false)

            Color.clear
                .frame(width: width, height: geo.size.height * 0.5)
                .contentShape(Rectangle())
                .position(x: x, y: y)
                .gesture(drag)
        }
        .accessibilityHidden(true)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                progress = min(max(inward(value.translation.width) / travel, 0), 1)
            }
            .onEnded { value in
                let distance = inward(value.translation.width)
                let flung = inward(value.predictedEndTranslation.width)
                if distance > 56 || flung > 140 {
                    onSwipe()
                }
                withAnimation(Motion.quick(reduced: reduceMotion)) { progress = 0 }
            }
    }

    private func inward(_ dx: CGFloat) -> CGFloat {
        edge == .trailing ? -dx : dx
    }
}
