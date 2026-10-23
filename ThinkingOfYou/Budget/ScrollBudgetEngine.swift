//  ScrollBudgetEngine.swift
//  ThinkingOfYou/Budget — the scroll-budget rules. Pure and deterministic:
//  every call takes the current `Date`, and the `Calendar` is injected.
//
//  Rules
//  - 600 s daily allowance, resetting at local midnight.
//  - Vault: every completed calendar day (strictly before today) on which 0 s
//    were spent earns +600 s, including days the app was never opened.
//    `lastEvaluatedDay` tracks how far the payout has got. A fresh install
//    earns nothing for days before it.
//  - A session can start only while daily remaining + vault > 0.
//  - `tick` spends the daily allowance first, then the vault. Any spend marks
//    today as used (no vault for today). When nothing is left the session ends.

import Foundation

struct ScrollBudgetEngine: Sendable {
    static let defaultDailyAllowance: TimeInterval = 600
    static let defaultVaultReward: TimeInterval = 600

    /// Below this many seconds the budget counts as empty (float dust).
    static let epsilon: TimeInterval = 0.001

    struct TickResult: Equatable, Sendable {
        var spentFromDaily: TimeInterval = 0
        var spentFromVault: TimeInterval = 0
        /// True when this tick used up the last of the budget and ended the session.
        var sessionEnded = false
    }

    private(set) var state: BudgetState
    var calendar: Calendar
    let dailyAllowance: TimeInterval
    let vaultReward: TimeInterval

    init(state: BudgetState = BudgetState(),
         calendar: Calendar = .current,
         dailyAllowance: TimeInterval = ScrollBudgetEngine.defaultDailyAllowance,
         vaultReward: TimeInterval = ScrollBudgetEngine.defaultVaultReward) {
        self.state = state
        self.calendar = calendar
        self.dailyAllowance = dailyAllowance
        self.vaultReward = vaultReward
    }

    // MARK: Derived values (call `evaluate(now:)` first for an up-to-date view)

    var dailyRemaining: TimeInterval { max(0, dailyAllowance - state.usedToday) }
    var vault: TimeInterval { max(0, state.vault) }
    var totalRemaining: TimeInterval { dailyRemaining + vault }
    var isSessionActive: Bool { state.sessionActive }
    var canStartSession: Bool { totalRemaining > Self.epsilon }

    /// Whether today already has spend on it (and so cannot earn vault time).
    var isTodayUsed: Bool { state.usedToday > 0 }

    // MARK: Day rollover and vault payout

    /// Rolls the day over at midnight and pays the vault for every completed,
    /// unused day since the last evaluation. Returns the seconds earned.
    @discardableResult
    mutating func evaluate(now: Date) -> TimeInterval {
        let today = DayStamp(now, calendar: calendar)

        guard let lastEvaluated = state.lastEvaluatedDay else {
            // First run: nothing before today can earn.
            state.installDay = today
            state.lastEvaluatedDay = today.adding(days: -1, calendar: calendar)
            state.currentDay = today
            state.usedToday = 0
            return 0
        }

        var earned: TimeInterval = 0
        let yesterday = today.adding(days: -1, calendar: calendar)
        if lastEvaluated < yesterday {
            // Completed days still to pay: (lastEvaluated, yesterday].
            var earningDays = max(0, lastEvaluated.days(until: yesterday, calendar: calendar))
            // Only `currentDay` can carry spend; if it falls in that range and
            // was used, it earns nothing.
            if let current = state.currentDay, current > lastEvaluated, current <= yesterday, state.usedToday > 0 {
                earningDays -= 1
            }
            earningDays = max(0, earningDays)
            earned = TimeInterval(earningDays) * vaultReward
            state.vault = max(0, state.vault) + earned
            state.unusedDaysEarned += earningDays
            state.lastEvaluatedDay = yesterday
        }

        if let current = state.currentDay {
            if current < today {
                state.currentDay = today
                state.usedToday = 0
            }
            // current > today means the clock went backwards: keep the usage
            // so moving the clock can't refund spent time.
        } else {
            state.currentDay = today
            state.usedToday = 0
        }
        return earned
    }

    // MARK: Sessions

    /// Starts a session if there is any time left. Returns whether one is running.
    @discardableResult
    mutating func startSession(now: Date) -> Bool {
        evaluate(now: now)
        guard canStartSession else {
            state.sessionActive = false
            return false
        }
        state.sessionActive = true
        return true
    }

    mutating func endSession() {
        state.sessionActive = false
    }

    /// Spends `seconds` of an active session: daily allowance first, then the
    /// vault. Ends the session when the budget reaches zero.
    @discardableResult
    mutating func tick(seconds: TimeInterval, now: Date) -> TickResult {
        evaluate(now: now)
        var result = TickResult()
        guard state.sessionActive else { return result }

        var toSpend = seconds.isFinite ? max(0, seconds) : 0
        let fromDaily = min(toSpend, dailyRemaining)
        state.usedToday += fromDaily
        toSpend -= fromDaily

        let fromVault = min(toSpend, vault)
        state.vault = vault - fromVault

        result.spentFromDaily = fromDaily
        result.spentFromVault = fromVault

        if totalRemaining <= Self.epsilon {
            // Snap float dust to an exact zero.
            state.usedToday = max(state.usedToday, dailyAllowance)
            state.vault = 0
            state.sessionActive = false
            result.sessionEnded = true
        }
        return result
    }
}
