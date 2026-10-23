//  RootView.swift
//  ThinkingOfYou/UI — the mode shell. A top bar (mode pill, budget pill,
//  settings) over both modes, which stay alive side by side so the
//  Instagram login and page survive every switch.
//
//  Quick swap: tap the pill, swipe sideways on the top bar, or drag in from
//  the screen edge (right edge in Instagram, left edge in Messages).
//
//  Must stay `RootView()` with no parameters: ThinkingOfYouApp creates it and
//  injects `AppEnvironment` via `.environment(env)`.

import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingSettings = false
    @State private var edgeProgress: CGFloat = 0
    @State private var showingSent = false
    @State private var sentCount = 0

    var body: some View {
        @Bindable var messages = env.messages
        let mode = env.shell.mode

        VStack(spacing: 0) {
            topBar
            if let notice = env.budget.earnedNotice {
                EarnedNoticeBanner(text: notice) {
                    withAnimation(Motion.gentle(reduced: reduceMotion)) {
                        env.budget.dismissEarnedNotice()
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            ZStack {
                InstagramView(model: env.instagram, budget: env.budget)
                    .modeLayer(isActive: mode == .instagram,
                               restingOffset: -28,
                               tug: mode == .instagram ? -18 * edgeProgress : 0)

                MessagesView(people: env.people,
                             messages: env.messages,
                             snippets: env.snippets,
                             nudges: env.nudges)
                    .modeLayer(isActive: mode == .messages,
                               restingOffset: 28,
                               tug: mode == .messages ? 18 * edgeProgress : 0)

                EdgeSwipeStrip(edge: mode == .instagram ? .trailing : .leading,
                               target: mode.other,
                               reduceMotion: reduceMotion,
                               progress: $edgeProgress) {
                    choose(mode.other)
                }
                .zIndex(2)
            }
            .animation(Motion.gentle(reduced: reduceMotion), value: mode)
        }
        .background(Theme.paper.ignoresSafeArea())
        .tint(Theme.wine)
        .animation(Motion.gentle(reduced: reduceMotion), value: env.budget.earnedNotice)
        .sensoryFeedback(.selection, trigger: mode)
        .sensoryFeedback(.success, trigger: sentCount)
        .overlay(alignment: .bottom) {
            if showingSent {
                ToastCapsule(text: "Message sent", systemImage: "heart.fill")
                    .padding(.bottom, Space.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: env.settings)
        }
        .sheet(item: $messages.composer) { draft in
            MessageComposer(draft: draft) { outcome in
                messages.composerFinished(outcome)
            }
            .ignoresSafeArea()
        }
        .alert("Missing contact details",
               isPresented: Binding(
                   get: { messages.alertMessage != nil },
                   set: { if !$0 { messages.dismissAlert() } }
               )) {
            Button("OK", role: .cancel) { messages.dismissAlert() }
        } message: {
            Text(messages.alertMessage ?? "")
        }
        .onChange(of: messages.composer) { _, newValue in
            if newValue == nil, messages.lastOutcome == .sent {
                flashSent()
            }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: Space.s) {
            ViewThatFits(in: .horizontal) {
                ModePill(mode: env.shell.mode, compact: false) { choose($0) }
                ModePill(mode: env.shell.mode, compact: true) { choose($0) }
            }
            .layoutPriority(1)

            Spacer(minLength: Space.xs)

            BudgetPillView(budget: env.budget)

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, Space.m)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.s)
        .background(Theme.paper)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) > abs(value.translation.height), abs(dx) > 40 else { return }
                    // Instagram is the left segment, Messages the right:
                    // swipe left to move right, like turning a page.
                    choose(dx < 0 ? .messages : .instagram)
                }
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    // MARK: Actions

    private func choose(_ newMode: AppMode) {
        guard newMode != env.shell.mode else { return }
        withAnimation(Motion.gentle(reduced: reduceMotion)) {
            env.shell.select(newMode)
        }
    }

    private func flashSent() {
        sentCount += 1
        let ticket = sentCount
        withAnimation(Motion.gentle(reduced: reduceMotion)) { showingSent = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard ticket == sentCount else { return }
            withAnimation(Motion.gentle(reduced: reduceMotion)) { showingSent = false }
        }
    }
}

// MARK: - Mode layer

private extension View {
    /// Keeps a mode view alive but hidden, nudged sideways, untouchable and
    /// silent to VoiceOver while the other mode is showing.
    func modeLayer(isActive: Bool, restingOffset: CGFloat, tug: CGFloat) -> some View {
        self
            .opacity(isActive ? 1 : 0)
            .offset(x: (isActive ? 0 : restingOffset) + tug)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .zIndex(isActive ? 1 : 0)
    }
}

// MARK: - Earned notice

private struct EarnedNoticeBanner: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: "heart.text.square.fill")
                .font(.title3)
                .foregroundStyle(Theme.wine)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(Space.m + 2)
        .background(
            RoundedRectangle(cornerRadius: Radius.small + 4, style: .continuous)
                .fill(Theme.blush)
        )
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Messages") {
    RootView()
        .environment(AppEnvironment.preview())
}

#Preview("Instagram") {
    RootView()
        .environment(AppEnvironment.preview(mode: .instagram))
}
