//  InstagramView.swift
//  ThinkingOfYou/UI — the caged Instagram web view with a slim chrome strip
//  (Back, lock state, Reload, Notifications, Inbox with unread badge), a
//  first-load state, a retry state and the cage's toasts.

import SwiftUI

struct InstagramView: View {
    let model: InstagramViewModel
    let budget: BudgetViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inboxTaps = 0

    var body: some View {
        VStack(spacing: 0) {
            chrome
            ZStack {
                InstagramWebContainer(model: model)
                    .ignoresSafeArea(edges: .bottom)

                if let error = model.loadError {
                    errorState(error)
                        .transition(.opacity)
                } else if model.currentURL == nil {
                    firstLoad
                        .transition(.opacity)
                }
            }
            .animation(Motion.gentle(reduced: reduceMotion), value: model.loadError)
            .animation(Motion.gentle(reduced: reduceMotion), value: model.currentURL == nil)
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    ToastCapsule(text: toast, systemImage: "lock.fill")
                        .padding(.bottom, 76) // clears Instagram's own bottom bar
                        .onTapGesture { model.dismissToast() }
                        .accessibilityAction(named: "Dismiss") { model.dismissToast() }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(toast)
                }
            }
            .animation(Motion.gentle(reduced: reduceMotion), value: model.toast)
        }
        .background(Theme.paper)
        .sensoryFeedback(.impact(weight: .light), trigger: inboxTaps)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: model.toast) { _, new in new != nil }
    }

    // MARK: Chrome strip

    private var chrome: some View {
        HStack(spacing: Space.xs) {
            Button {
                model.goBack()
            } label: {
                Image(systemName: "chevron.backward")
                    .chromeIcon()
            }
            .disabled(!model.canGoBack)
            .opacity(model.canGoBack ? 1 : 0.35)
            .accessibilityLabel("Back")

            lockLabel
                .padding(.leading, Space.xs)

            Spacer(minLength: Space.s)

            Button {
                model.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .chromeIcon()
            }
            .accessibilityLabel("Reload")

            Button {
                model.goActivity()
            } label: {
                Image(systemName: "bell")
                    .chromeIcon()
            }
            .accessibilityLabel("Notifications")

            Button {
                inboxTaps += 1
                model.goInbox()
            } label: {
                Image(systemName: model.isAtInbox ? "paperplane.fill" : "paperplane")
                    .chromeIcon(active: model.isAtInbox)
                    .overlay(alignment: .topTrailing) {
                        if model.unreadCount > 0 {
                            Text(model.unreadCount > 9 ? "9+" : "\(model.unreadCount)")
                                .font(.toyNumber(.caption2, weight: .bold))
                                .foregroundStyle(Theme.onRose)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Capsule().fill(Theme.roseFill))
                                .offset(x: 4, y: -2)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
            }
            .accessibilityLabel("Inbox")
            .accessibilityValue(model.unreadCount > 0 ? "\(model.unreadCount) unread" : "")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Space.m)
        .frame(height: 44)
        .background(Theme.paper)
        .overlay(alignment: .bottom) {
            progressLine
        }
        .animation(Motion.quick(reduced: reduceMotion), value: model.unreadCount)
    }

    private var lockLabel: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: budget.isUnlocked ? "lock.open.fill" : "lock.fill")
                .font(.caption.weight(.semibold))
            Text(budget.isUnlocked ? "Feed open" : "Messages only")
                .font(.toyLabel(.footnote))
                .lineLimit(1)
        }
        .foregroundStyle(budget.isUnlocked ? Theme.wine : Theme.inkSoft)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(budget.isUnlocked ? "Feed and Reels are open" : "Feed and Reels are locked")
    }

    private var progressLine: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.hairline)
                if model.isLoading {
                    Rectangle()
                        .fill(Theme.rose)
                        .frame(width: geo.size.width * min(max(model.progress, 0.05), 1))
                        .animation(.easeOut(duration: 0.25), value: model.progress)
                        .transition(.opacity)
                }
            }
        }
        .frame(height: model.isLoading ? 2 : 1)
        .animation(.easeOut(duration: 0.3), value: model.isLoading)
        .accessibilityHidden(true)
    }

    // MARK: States

    private var firstLoad: some View {
        VStack(spacing: Space.l) {
            Image(systemName: "heart.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.rose)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                .accessibilityHidden(true)
            Text("Opening your inbox")
                .font(.toyDisplay(.title3))
                .foregroundStyle(Theme.ink)
            Text("Sign in once and Instagram stays signed in here.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .accessibilityElement(children: .combine)
    }

    private func errorState(_ message: String) -> some View {
        VStack {
            NoticeCard(systemImage: "wifi.exclamationmark",
                       title: "Instagram didn't load",
                       message: message,
                       buttonTitle: "Try again") {
                model.reload()
            }
            .padding(Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
    }
}

private extension Image {
    func chromeIcon(active: Bool = false) -> some View {
        self
            .font(.body.weight(.medium))
            .foregroundStyle(active ? Theme.wine : Theme.ink)
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
    }
}

#Preview {
    let env = AppEnvironment.preview(mode: .instagram)
    return InstagramView(model: env.instagram, budget: env.budget)
        .environment(env)
}
