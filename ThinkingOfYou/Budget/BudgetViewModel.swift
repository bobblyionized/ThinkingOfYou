//  BudgetViewModel.swift
//  ThinkingOfYou/Budget — observable wrapper around ScrollBudgetEngine.
//  A 1 s timer spends the budget only while a session is active AND the app
//  is in the foreground AND Instagram mode is showing.

import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class BudgetViewModel {
    // MARK: State (read-only for views)

    /// Seconds left of today's 10 minutes.
    private(set) var dailyRemaining: TimeInterval
    /// Banked seconds from unused days.
    private(set) var vault: TimeInterval
    /// True while a scroll session is running (the Instagram cage is open).
    private(set) var isUnlocked = false
    /// True while the 1 s timer is actually spending time.
    private(set) var isTicking = false
    /// Lifetime number of unused days that paid into the vault.
    private(set) var unusedDaysEarned = 0
    /// One-shot message after a rollover paid the vault ("+20 min banked ...").
    /// Views show it and call `dismissEarnedNotice()`.
    private(set) var earnedNotice: String? = nil

    private(set) var isForeground = true
    private(set) var isInstagramActive = false

    let dailyAllowance: TimeInterval

    // MARK: Derived

    var totalRemaining: TimeInterval { dailyRemaining + vault }
    var canStart: Bool { !isUnlocked && totalRemaining > ScrollBudgetEngine.epsilon }
    /// 1 when the whole daily allowance is left, 0 when it's gone.
    var dailyFraction: Double {
        dailyAllowance > 0 ? min(1, max(0, dailyRemaining / dailyAllowance)) : 0
    }
    var isOutOfTime: Bool { totalRemaining <= ScrollBudgetEngine.epsilon }

    var dailyRemainingText: String { BudgetFormat.clock(dailyRemaining) }
    var vaultText: String { BudgetFormat.clock(vault) }
    var totalRemainingText: String { BudgetFormat.clock(totalRemaining) }
    var vaultShortText: String { BudgetFormat.short(vault) }

    /// One line for the budget pill.
    var statusText: String {
        if isUnlocked {
            if !isTicking { return "Paused · \(totalRemainingText) left" }
            return dailyRemaining > 0
                ? "Scrolling · \(dailyRemainingText) left today"
                : "Scrolling · \(vaultText) from the vault"
        }
        if isOutOfTime { return "Out of scroll time · back tomorrow" }
        if vault > 0 { return "Locked · \(dailyRemainingText) today + \(vaultShortText) vault" }
        return "Locked · \(dailyRemainingText) today"
    }

    // MARK: Wiring

    /// Called with the new lock state whenever `isUnlocked` flips.
    @ObservationIgnored var onLockChange: (@MainActor (_ unlocked: Bool) -> Void)? = nil

    @ObservationIgnored private var engine: ScrollBudgetEngine
    private let store: BudgetStore
    private let now: () -> Date
    @ObservationIgnored private var timer: Timer? = nil
    @ObservationIgnored private var midnightTimer: Timer? = nil
    @ObservationIgnored private var lastTick: Date? = nil
    @ObservationIgnored private var timeObservers: [NSObjectProtocol] = []

    /// `calendar` defaults to `.autoupdatingCurrent`, so midnight follows the
    /// device's time zone as it changes.
    init(defaults: UserDefaults = .standard,
         calendar: Calendar = .autoupdatingCurrent,
         now: @escaping () -> Date = { Date() }) {
        let store = BudgetStore(defaults: defaults)
        var engine = ScrollBudgetEngine(state: store.load() ?? BudgetState(), calendar: calendar)
        // A fresh launch always starts locked.
        engine.endSession()
        let earned = engine.evaluate(now: now())
        store.save(engine.state)

        self.store = store
        self.engine = engine
        self.now = now
        self.dailyAllowance = engine.dailyAllowance
        self.dailyRemaining = engine.dailyRemaining
        self.vault = engine.vault
        self.unusedDaysEarned = engine.state.unusedDaysEarned
        // Cold launch after skipped days: show the payout too.
        if earned > 0 {
            self.earnedNotice = Self.earnedNoticeText(earned)
        }
        observeTimeChanges()
    }

    /// Wording shared by launch and `refresh()`.
    nonisolated static func earnedNoticeText(_ earned: TimeInterval) -> String {
        "+\(BudgetFormat.short(earned)) banked for days you skipped scrolling"
    }

    // MARK: Actions

    /// Starts a scroll session. Returns false when there's no time left.
    @discardableResult
    func start() -> Bool {
        let started = engine.startSession(now: now())
        persistAndPublish()
        return started
    }

    /// Ends the session early (re-locks).
    func stop() {
        engine.endSession()
        persistAndPublish()
    }

    /// Re-evaluates the day (midnight rollover, vault payout). Call on foreground.
    func refresh() {
        let earned = engine.evaluate(now: now())
        if earned > 0 {
            earnedNotice = Self.earnedNoticeText(earned)
        }
        persistAndPublish()
    }

    func dismissEarnedNotice() {
        earnedNotice = nil
    }

    func setForeground(_ foreground: Bool) {
        guard foreground != isForeground else { return }
        isForeground = foreground
        if foreground { refresh() } else { updateTimer() }
    }

    func setInstagramActive(_ active: Bool) {
        guard active != isInstagramActive else { return }
        isInstagramActive = active
        updateTimer()
    }

    /// Spends `seconds` right away (what the timer does each second).
    /// Exposed for tests and previews.
    func advance(by seconds: TimeInterval) {
        engine.tick(seconds: seconds, now: now())
        persistAndPublish()
    }

    // MARK: Internals

    private var shouldTick: Bool { isUnlocked && isForeground && isInstagramActive }

    private func persistAndPublish() {
        store.save(engine.state)
        let wasUnlocked = isUnlocked
        if dailyRemaining != engine.dailyRemaining { dailyRemaining = engine.dailyRemaining }
        if vault != engine.vault { vault = engine.vault }
        if unusedDaysEarned != engine.state.unusedDaysEarned { unusedDaysEarned = engine.state.unusedDaysEarned }
        if isUnlocked != engine.isSessionActive { isUnlocked = engine.isSessionActive }
        updateTimer()
        scheduleMidnightRefresh()
        if wasUnlocked != isUnlocked {
            onLockChange?(isUnlocked)
        }
    }

    private func updateTimer() {
        if shouldTick {
            guard timer == nil else { return }
            lastTick = now()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.timerFired()
                }
            }
            timer.tolerance = 0.1
            // .common so it keeps firing while the user's finger is scrolling.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            isTicking = true
        } else {
            timer?.invalidate()
            timer = nil
            lastTick = nil
            if isTicking { isTicking = false }
        }
    }

    private func timerFired() {
        guard shouldTick else {
            updateTimer()
            return
        }
        let current = now()
        // Wall-clock delta, clamped so a stall or suspension never bills more
        // than a few seconds at once.
        let elapsed = min(3, max(0, current.timeIntervalSince(lastTick ?? current)))
        lastTick = current
        guard elapsed > 0 else { return }
        engine.tick(seconds: elapsed, now: current)
        persistAndPublish()
    }

    /// Time zone or clock changes move "midnight": drop the pending midnight
    /// timer and re-evaluate (which reschedules it).
    private func observeTimeChanges() {
        let names: [Notification.Name] = [.NSSystemTimeZoneDidChange, UIApplication.significantTimeChangeNotification]
        timeObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.timeDidChange()
                }
            }
        }
    }

    private func timeDidChange() {
        midnightTimer?.invalidate()
        midnightTimer = nil
        refresh()
    }

    /// Refreshes the numbers right after local midnight even if the app just
    /// sits open.
    private func scheduleMidnightRefresh() {
        guard midnightTimer == nil else { return }
        let calendar = engine.calendar
        let today = DayStamp(now(), calendar: calendar)
        let fireDate = today.adding(days: 1, calendar: calendar).startDate(in: calendar).addingTimeInterval(1)
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.midnightTimer = nil
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }
}
