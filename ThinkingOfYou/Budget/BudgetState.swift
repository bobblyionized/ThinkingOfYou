//  BudgetState.swift
//  ThinkingOfYou/Budget — persisted scroll-budget state and the calendar-day
//  type it is keyed by. Pure value types, no UIKit.

import Foundation

/// A calendar day (year, month, day) in the calendar it was created with.
/// Stored instead of a `Date` so that a recorded day never shifts when the
/// time zone changes.
struct DayStamp: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Local midnight that starts this day.
    func startDate(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
            ?? Date(timeIntervalSince1970: 0)
    }

    /// Noon of this day: a safe anchor for day arithmetic across DST changes.
    private func noon(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
            ?? startDate(in: calendar)
    }

    func adding(days: Int, calendar: Calendar) -> DayStamp {
        let anchor = noon(in: calendar)
        let moved = calendar.date(byAdding: .day, value: days, to: anchor) ?? anchor
        return DayStamp(moved, calendar: calendar)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    func days(until other: DayStamp, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: noon(in: calendar), to: other.noon(in: calendar)).day ?? 0
    }

    static func < (lhs: DayStamp, rhs: DayStamp) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

/// Everything the scroll budget remembers between launches.
struct BudgetState: Codable, Equatable, Sendable {
    /// The day `usedToday` belongs to.
    var currentDay: DayStamp?
    /// Seconds of the daily allowance spent on `currentDay`.
    var usedToday: TimeInterval
    /// Banked seconds earned by unused days.
    var vault: TimeInterval
    /// Every completed day up to and including this one has been paid out.
    /// `nil` until the first evaluation (fresh install).
    var lastEvaluatedDay: DayStamp?
    /// True while a scroll session is running.
    var sessionActive: Bool
    /// The day the budget was first evaluated.
    var installDay: DayStamp?
    /// Lifetime count of unused days that earned vault time.
    var unusedDaysEarned: Int

    init(currentDay: DayStamp? = nil,
         usedToday: TimeInterval = 0,
         vault: TimeInterval = 0,
         lastEvaluatedDay: DayStamp? = nil,
         sessionActive: Bool = false,
         installDay: DayStamp? = nil,
         unusedDaysEarned: Int = 0) {
        self.currentDay = currentDay
        self.usedToday = usedToday
        self.vault = vault
        self.lastEvaluatedDay = lastEvaluatedDay
        self.sessionActive = sessionActive
        self.installDay = installDay
        self.unusedDaysEarned = unusedDaysEarned
    }

    private enum CodingKeys: String, CodingKey {
        case currentDay, usedToday, vault, lastEvaluatedDay, sessionActive, installDay, unusedDaysEarned
    }

    // Tolerant decoding: keys added in later versions fall back to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentDay = try c.decodeIfPresent(DayStamp.self, forKey: .currentDay)
        usedToday = try c.decodeIfPresent(TimeInterval.self, forKey: .usedToday) ?? 0
        vault = try c.decodeIfPresent(TimeInterval.self, forKey: .vault) ?? 0
        lastEvaluatedDay = try c.decodeIfPresent(DayStamp.self, forKey: .lastEvaluatedDay)
        sessionActive = try c.decodeIfPresent(Bool.self, forKey: .sessionActive) ?? false
        installDay = try c.decodeIfPresent(DayStamp.self, forKey: .installDay)
        unusedDaysEarned = try c.decodeIfPresent(Int.self, forKey: .unusedDaysEarned) ?? 0
    }
}

/// JSON persistence of `BudgetState` in UserDefaults.
struct BudgetStore {
    static let defaultsKey = "budgetState.v1"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> BudgetState? {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return nil }
        return try? JSONDecoder().decode(BudgetState.self, from: data)
    }

    func save(_ state: BudgetState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// Human-readable durations for the budget UI.
enum BudgetFormat {
    /// "9:59", "0:05", "1:20:00". Rounds partial seconds up so a running
    /// countdown never shows 0:00 while time is left.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// "10 min", "1 h", "1 h 20 min", "45 s".
    static func short(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.up))
        if total < 60 { return "\(total) s" }
        let minutes = (total + 59) / 60
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}
