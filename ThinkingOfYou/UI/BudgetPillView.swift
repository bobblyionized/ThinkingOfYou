//  BudgetPillView.swift
//  ThinkingOfYou/UI — the scroll-budget pill in the top bar, and the budget
//  sheet it opens (the draining heart, today + vault, start/end session).

import SwiftUI

// MARK: - Pill

struct BudgetPillView: View {
    let budget: BudgetViewModel
    /// Owned by RootView so it can close this sheet for the composer.
    @Binding var isPresentingSheet: Bool

    var body: some View {
        Button {
            isPresentingSheet = true
        } label: {
            pillLabel
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresentingSheet) {
            BudgetSheetView(budget: budget)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Radius.large)
        }
        .accessibilityLabel("Scroll budget")
        .accessibilityValue(budget.statusText)
        .accessibilityHint("Shows your time and starts or ends a scroll session")
    }

    private var timeText: String {
        budget.isUnlocked ? budget.totalRemainingText : budget.dailyRemainingText
    }

    private var pillLabel: some View {
        HStack(spacing: Space.xs + 2) {
            DrainingHeart(
                fraction: budget.dailyFraction,
                fill: budget.isUnlocked ? Theme.onRose : Theme.rose,
                empty: budget.isUnlocked ? Theme.onRose.opacity(0.32) : Theme.blush
            )
            .frame(width: 15)

            Text(timeText)
                .font(.toyNumber(.subheadline))
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: timeText)
                .lineLimit(1)

            if budget.isUnlocked && !budget.isTicking {
                Image(systemName: "pause.fill")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            } else if budget.vault > 0 && !budget.isUnlocked {
                Text("+")
                    .font(.toyNumber(.caption))
                    .foregroundStyle(Theme.wine)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(budget.isUnlocked ? Theme.onRose : Theme.ink)
        .opacity(budget.isOutOfTime && !budget.isUnlocked ? 0.55 : 1)
        .padding(.horizontal, Space.m)
        .frame(minHeight: 36)
        .background(
            Capsule().fill(budget.isUnlocked ? Theme.roseFill : Theme.card)
        )
        .overlay(
            Capsule().strokeBorder(budget.isUnlocked ? Color.clear : Theme.hairline, lineWidth: 1)
        )
        .contentShape(Capsule())
        .animation(Motion.snap, value: budget.isUnlocked)
    }
}

// MARK: - Sheet

struct BudgetSheetView: View {
    let budget: BudgetViewModel
    @ScaledMetric(relativeTo: .largeTitle) private var heartWidth: CGFloat = 132
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 46

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                header
                heart
                ledger
                actions
                Text("Messages, notes and stories are always open. Today's minutes reset at midnight and are spent before the vault.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.l)
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.xxl)
            .padding(.bottom, Space.xl)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.paper.ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .medium), trigger: budget.isUnlocked)
    }

    // MARK: Parts

    private var headline: String {
        if budget.isUnlocked { return budget.isTicking ? "Feeds are open" : "Session paused" }
        if budget.isOutOfTime { return "That's today's scrolling" }
        return "Feeds are resting"
    }

    private var header: some View {
        Text(headline)
            .font(.toyDisplay(.title))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
    }

    private var heart: some View {
        VStack(spacing: Space.s) {
            DrainingHeart(fraction: budget.dailyFraction, lineWidth: 1.5)
                .frame(width: heartWidth)
                .padding(.bottom, Space.s)

            Text(budget.isUnlocked ? budget.totalRemainingText : budget.dailyRemainingText)
                .font(.system(size: clockSize, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(budget.isUnlocked ? Theme.wine : Theme.ink)
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: budget.totalRemainingText)

            Text(budget.isUnlocked ? "left in this session" : "left today")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time left")
        .accessibilityValue(budget.statusText)
    }

    private var ledger: some View {
        VStack(spacing: 0) {
            LedgerRow(title: "Today",
                      value: budget.dailyRemainingText,
                      note: "of \(Int(budget.dailyAllowance / 60)) min")
            Divider().overlay(Theme.hairline)
            LedgerRow(title: "Vault",
                      value: budget.vaultText,
                      note: vaultNote)
        }
        .padding(.horizontal, Space.l)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private var vaultNote: String {
        switch budget.unusedDaysEarned {
        case 0: return "Skip scrolling for a whole day to bank 10 min"
        case 1: return "Banked from 1 day without scrolling"
        default: return "Banked from \(budget.unusedDaysEarned) days without scrolling"
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: Space.m) {
            if budget.isUnlocked {
                Button("End session") { budget.stop() }
                    .buttonStyle(.rose)
            } else if budget.canStart {
                Button("Start scrolling") { _ = budget.start() }
                    .buttonStyle(.rose)
            } else {
                Button("No scroll time left today") {}
                    .buttonStyle(.rose)
                    .disabled(true)
            }

            if let note = actionNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(budget.isUnlocked ? Theme.wine : Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionNote: String? {
        if budget.isUnlocked {
            if !budget.isTicking { return "The clock only runs while Instagram is on screen." }
            if budget.dailyRemaining <= 0 { return "Today's minutes are used up, so this is coming from the vault." }
            return "Ending early keeps the rest for later today."
        }
        if budget.canStart {
            return "Starting opens the feed and Reels until you end the session or the time runs out."
        }
        return nil
    }
}

private struct LedgerRow: View {
    let title: String
    let value: String
    let note: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title)
                    .font(.toyDisplay(.headline))
                    .foregroundStyle(Theme.ink)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            Text(value)
                .font(.toyNumber(.title3))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: value)
        }
        .padding(.vertical, Space.m + 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Pill") {
    BudgetPillView(budget: AppEnvironment.preview().budget, isPresentingSheet: .constant(false))
        .padding()
        .background(Theme.paper)
}

#Preview("Sheet") {
    BudgetSheetView(budget: AppEnvironment.preview().budget)
}
