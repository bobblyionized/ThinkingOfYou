import XCTest
@testable import ThinkingOfYou

final class ScrollBudgetEngineTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    /// An engine already installed (first evaluated) at `installedAt`.
    private func installedEngine(at installedAt: Date) -> ScrollBudgetEngine {
        var engine = ScrollBudgetEngine(calendar: calendar)
        engine.evaluate(now: installedAt)
        return engine
    }

    // MARK: First install

    func testFirstInstallEarnsNothingForPastDays() {
        var engine = ScrollBudgetEngine(calendar: calendar)
        let earned = engine.evaluate(now: date(2026, 10, 22, 9))
        XCTAssertEqual(earned, 0)
        XCTAssertEqual(engine.vault, 0)
        XCTAssertEqual(engine.dailyRemaining, 600)
        XCTAssertEqual(engine.state.installDay, DayStamp(year: 2026, month: 10, day: 22))
        XCTAssertEqual(engine.state.lastEvaluatedDay, DayStamp(year: 2026, month: 10, day: 21))
        XCTAssertEqual(engine.state.currentDay, DayStamp(year: 2026, month: 10, day: 22))
    }

    func testInstallDayItselfCanEarnOnceCompleted() {
        var engine = installedEngine(at: date(2026, 10, 22, 23, 50))
        XCTAssertEqual(engine.evaluate(now: date(2026, 10, 23, 8)), 600)
        XCTAssertEqual(engine.vault, 600)
    }

    // MARK: Daily reset

    func testDailyAllowanceResetsAtLocalMidnight() {
        var engine = installedEngine(at: date(2026, 10, 22, 20))
        XCTAssertTrue(engine.startSession(now: date(2026, 10, 22, 23, 50)))
        engine.tick(seconds: 450, now: date(2026, 10, 22, 23, 58))
        XCTAssertEqual(engine.dailyRemaining, 150, accuracy: 0.0001)

        // One second before midnight: still the same day.
        engine.evaluate(now: date(2026, 10, 22, 23, 59, 59))
        XCTAssertEqual(engine.dailyRemaining, 150, accuracy: 0.0001)

        // Just after midnight: fresh 600 s, and the used day earned nothing.
        engine.evaluate(now: date(2026, 10, 23, 0, 0, 1))
        XCTAssertEqual(engine.dailyRemaining, 600)
        XCTAssertEqual(engine.vault, 0)
    }

    func testEvaluateIsIdempotentWithinADay() {
        var engine = installedEngine(at: date(2026, 10, 22))
        XCTAssertEqual(engine.evaluate(now: date(2026, 10, 24, 1)), 1200)
        XCTAssertEqual(engine.evaluate(now: date(2026, 10, 24, 9)), 0)
        XCTAssertEqual(engine.evaluate(now: date(2026, 10, 24, 23, 59)), 0)
        XCTAssertEqual(engine.vault, 1200)
    }

    // MARK: Vault

    func testUnusedDayEarnsTenMinutes() {
        var engine = installedEngine(at: date(2026, 10, 22, 9))
        XCTAssertEqual(engine.evaluate(now: date(2026, 10, 23, 9)), 600)
        XCTAssertEqual(engine.vault, 600)
        XCTAssertEqual(engine.state.unusedDaysEarned, 1)
    }

    func testMultiDayCatchUpIncludesDaysTheAppWasNotOpened() {
        var engine = installedEngine(at: date(2026, 10, 22, 9))
        // Used on install day, then the app isn't opened until the 27th.
        engine.startSession(now: date(2026, 10, 22, 10))
        engine.tick(seconds: 30, now: date(2026, 10, 22, 10))
        engine.endSession()

        // Completed days: 22 (used), 23, 24, 25, 26 -> 4 unused.
        XCTAssertEqual(engine.evaluate(now: date(2026, 10, 27, 7)), 4 * 600)
        XCTAssertEqual(engine.vault, 2400)
        XCTAssertEqual(engine.state.lastEvaluatedDay, DayStamp(year: 2026, month: 10, day: 26))
    }

    func testWeekAwayEarnsSevenDays() {
        var engine = installedEngine(at: date(2026, 10, 1))
        XCTAssertEqual(engine.evaluate(now: date(2026, 10, 8)), 7 * 600)
    }

    func testCatchUpAcrossMonthAndYearBoundary() {
        var engine = installedEngine(at: date(2026, 12, 30))
        // 30, 31 Dec and 1 Jan completed.
        XCTAssertEqual(engine.evaluate(now: date(2027, 1, 2)), 3 * 600)
    }

    func testCatchUpAcrossDaylightSavingChange() {
        // DST ends in New York on 1 Nov 2026 (a 25-hour day).
        var engine = installedEngine(at: date(2026, 10, 31, 22))
        XCTAssertEqual(engine.evaluate(now: date(2026, 11, 3, 0, 30)), 3 * 600) // 31, 1, 2
        XCTAssertEqual(engine.state.currentDay, DayStamp(year: 2026, month: 11, day: 3))
    }

    func testUsedDayEarnsNothing() {
        var engine = installedEngine(at: date(2026, 10, 22, 9))
        engine.startSession(now: date(2026, 10, 22, 18))
        engine.tick(seconds: 1, now: date(2026, 10, 22, 18))
        engine.endSession()
        XCTAssertTrue(engine.isTodayUsed)
        XCTAssertEqual(engine.evaluate(now: date(2026, 10, 23, 9)), 0)
        XCTAssertEqual(engine.vault, 0)
    }

    func testSpendingIntoTheVaultMarksTheDayUsed() {
        var engine = ScrollBudgetEngine(state: BudgetState(vault: 1200), calendar: calendar)
        engine.evaluate(now: date(2026, 10, 22, 9))
        engine.startSession(now: date(2026, 10, 22, 9))
        engine.tick(seconds: 700, now: date(2026, 10, 22, 9, 15))
        XCTAssertEqual(engine.vault, 1100, accuracy: 0.0001)
        XCTAssertEqual(engine.evaluate(now: date(2026, 10, 23, 9)), 0)
    }

    func testStartingASessionWithoutSpendingDoesNotMarkTheDay() {
        var engine = installedEngine(at: date(2026, 10, 22, 9))
        XCTAssertTrue(engine.startSession(now: date(2026, 10, 22, 10)))
        engine.endSession()
        XCTAssertEqual(engine.evaluate(now: date(2026, 10, 23, 9)), 600)
    }

    // MARK: Spending

    func testSpendOrderIsDailyThenVault() {
        var engine = ScrollBudgetEngine(state: BudgetState(vault: 600), calendar: calendar)
        engine.evaluate(now: date(2026, 10, 22, 9))
        XCTAssertTrue(engine.startSession(now: date(2026, 10, 22, 9)))

        var result = engine.tick(seconds: 500, now: date(2026, 10, 22, 9, 10))
        XCTAssertEqual(result.spentFromDaily, 500, accuracy: 0.0001)
        XCTAssertEqual(result.spentFromVault, 0, accuracy: 0.0001)
        XCTAssertEqual(engine.dailyRemaining, 100, accuracy: 0.0001)
        XCTAssertEqual(engine.vault, 600, accuracy: 0.0001)

        // Crosses from daily into the vault within one tick.
        result = engine.tick(seconds: 250, now: date(2026, 10, 22, 9, 15))
        XCTAssertEqual(result.spentFromDaily, 100, accuracy: 0.0001)
        XCTAssertEqual(result.spentFromVault, 150, accuracy: 0.0001)
        XCTAssertEqual(engine.dailyRemaining, 0, accuracy: 0.0001)
        XCTAssertEqual(engine.vault, 450, accuracy: 0.0001)
        XCTAssertTrue(engine.isSessionActive)
    }

    func testSessionEndsWhenBudgetHitsZero() {
        var engine = installedEngine(at: date(2026, 10, 22, 9))
        XCTAssertTrue(engine.startSession(now: date(2026, 10, 22, 9)))
        for second in 0..<599 {
            let result = engine.tick(seconds: 1, now: date(2026, 10, 22, 9, 0, 0).addingTimeInterval(TimeInterval(second)))
            XCTAssertFalse(result.sessionEnded)
        }
        XCTAssertTrue(engine.isSessionActive)
        XCTAssertEqual(engine.dailyRemaining, 1, accuracy: 0.0001)

        let last = engine.tick(seconds: 5, now: date(2026, 10, 22, 9, 10))
        XCTAssertTrue(last.sessionEnded)
        XCTAssertEqual(last.spentFromDaily, 1, accuracy: 0.0001)
        XCTAssertFalse(engine.isSessionActive)
        XCTAssertEqual(engine.totalRemaining, 0)

        // Nothing left today: can't start again, ticks do nothing.
        XCTAssertFalse(engine.startSession(now: date(2026, 10, 22, 11)))
        XCTAssertEqual(engine.tick(seconds: 10, now: date(2026, 10, 22, 11)), ScrollBudgetEngine.TickResult())
    }

    func testSessionEndsAtZeroAfterDrainingTheVault() {
        var engine = ScrollBudgetEngine(state: BudgetState(vault: 60), calendar: calendar)
        engine.evaluate(now: date(2026, 10, 22, 9))
        engine.startSession(now: date(2026, 10, 22, 9))
        XCTAssertFalse(engine.tick(seconds: 630, now: date(2026, 10, 22, 9, 11)).sessionEnded)
        XCTAssertEqual(engine.vault, 30, accuracy: 0.0001)
        XCTAssertTrue(engine.tick(seconds: 30, now: date(2026, 10, 22, 9, 12)).sessionEnded)
        XCTAssertEqual(engine.vault, 0)
        XCTAssertFalse(engine.canStartSession)
    }

    func testFractionalTicksEndCleanly() {
        var engine = installedEngine(at: date(2026, 10, 22, 9))
        engine.startSession(now: date(2026, 10, 22, 9))
        var ended = false
        var ticks = 0
        while !ended && ticks < 10_000 {
            ended = engine.tick(seconds: 0.1, now: date(2026, 10, 22, 9, 30)).sessionEnded
            ticks += 1
        }
        XCTAssertTrue(ended)
        XCTAssertEqual(engine.totalRemaining, 0)
        XCTAssertLessThanOrEqual(abs(ticks - 6000), 1)
    }

    func testTickWithoutSessionSpendsNothing() {
        var engine = installedEngine(at: date(2026, 10, 22, 9))
        XCTAssertEqual(engine.tick(seconds: 100, now: date(2026, 10, 22, 10)), ScrollBudgetEngine.TickResult())
        XCTAssertEqual(engine.dailyRemaining, 600)
        XCTAssertFalse(engine.isTodayUsed)
    }

    func testCanStartWithOnlyVaultTime() {
        var engine = ScrollBudgetEngine(state: BudgetState(usedToday: 600, vault: 120), calendar: calendar)
        engine.evaluate(now: date(2026, 10, 22, 9))
        // First evaluation resets currentDay; simulate an exhausted day explicitly.
        engine.startSession(now: date(2026, 10, 22, 9))
        engine.tick(seconds: 600, now: date(2026, 10, 22, 9, 10))
        engine.endSession()
        XCTAssertEqual(engine.dailyRemaining, 0)
        XCTAssertEqual(engine.vault, 120, accuracy: 0.0001)
        XCTAssertTrue(engine.startSession(now: date(2026, 10, 22, 10)))
    }

    func testClockMovingBackwardsDoesNotRefundUsage() {
        var engine = installedEngine(at: date(2026, 10, 22, 9))
        engine.startSession(now: date(2026, 10, 22, 9))
        engine.tick(seconds: 400, now: date(2026, 10, 22, 9, 7))
        engine.evaluate(now: date(2026, 10, 21, 9))
        XCTAssertEqual(engine.dailyRemaining, 200, accuracy: 0.0001)
        XCTAssertEqual(engine.vault, 0)
    }

    // MARK: Persistence

    func testStateRoundTripsThroughJSON() throws {
        var engine = installedEngine(at: date(2026, 10, 22, 9))
        engine.evaluate(now: date(2026, 10, 25, 9))
        engine.startSession(now: date(2026, 10, 25, 9))
        engine.tick(seconds: 42, now: date(2026, 10, 25, 9, 1))
        let data = try JSONEncoder().encode(engine.state)
        let decoded = try JSONDecoder().decode(BudgetState.self, from: data)
        XCTAssertEqual(decoded, engine.state)
    }

    func testDecodingToleratesMissingKeys() throws {
        let json = #"{"vault": 1200, "lastEvaluatedDay": {"year": 2026, "month": 10, "day": 20}}"#
        let state = try JSONDecoder().decode(BudgetState.self, from: Data(json.utf8))
        XCTAssertEqual(state.vault, 1200)
        XCTAssertEqual(state.usedToday, 0)
        XCTAssertFalse(state.sessionActive)
        XCTAssertNil(state.currentDay)
    }

    func testFormatting() {
        XCTAssertEqual(BudgetFormat.clock(600), "10:00")
        XCTAssertEqual(BudgetFormat.clock(59.2), "1:00")
        XCTAssertEqual(BudgetFormat.clock(5), "0:05")
        XCTAssertEqual(BudgetFormat.clock(4800), "1:20:00")
        XCTAssertEqual(BudgetFormat.clock(-3), "0:00")
        XCTAssertEqual(BudgetFormat.short(600), "10 min")
        XCTAssertEqual(BudgetFormat.short(3600), "1 h")
        XCTAssertEqual(BudgetFormat.short(4800), "1 h 20 min")
        XCTAssertEqual(BudgetFormat.short(45), "45 s")
    }
}

// MARK: - BudgetViewModel

@MainActor
final class BudgetViewModelTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_792_000_000)
    private var defaults: UserDefaults?

    /// A fresh, isolated UserDefaults suite per test (shared across relaunches
    /// within the test).
    private func testDefaults() -> UserDefaults {
        if let defaults { return defaults }
        let name = "BudgetViewModelTests.\(UUID().uuidString)"
        let created = UserDefaults(suiteName: name)!
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        defaults = created
        return created
    }

    private func makeModel() -> BudgetViewModel {
        BudgetViewModel(defaults: testDefaults(), calendar: Calendar(identifier: .gregorian), now: { [unowned self] in self.clock })
    }

    func testStartSpendStopAndPersist() {
        let model = makeModel()
        var lockEvents: [Bool] = []
        model.onLockChange = { lockEvents.append($0) }

        XCTAssertFalse(model.isUnlocked)
        XCTAssertTrue(model.start())
        XCTAssertTrue(model.isUnlocked)
        model.advance(by: 90)
        XCTAssertEqual(model.dailyRemaining, 510, accuracy: 0.0001)
        XCTAssertEqual(model.dailyRemainingText, "8:30")
        model.stop()
        XCTAssertFalse(model.isUnlocked)
        XCTAssertEqual(lockEvents, [true, false])

        // A new launch sees the spend and starts locked.
        let relaunched = makeModel()
        XCTAssertEqual(relaunched.dailyRemaining, 510, accuracy: 0.0001)
        XCTAssertFalse(relaunched.isUnlocked)
    }

    func testRelocksWhenTimeRunsOut() {
        let model = makeModel()
        var lockEvents: [Bool] = []
        model.onLockChange = { lockEvents.append($0) }
        model.start()
        model.advance(by: 600)
        XCTAssertFalse(model.isUnlocked)
        XCTAssertTrue(model.isOutOfTime)
        XCTAssertFalse(model.canStart)
        XCTAssertFalse(model.start())
        XCTAssertEqual(lockEvents, [true, false])
    }

    func testTimerOnlyRunsInForegroundInstagramSessions() {
        let model = makeModel()
        model.setInstagramActive(true)
        XCTAssertFalse(model.isTicking)       // no session
        model.start()
        XCTAssertTrue(model.isTicking)
        model.setForeground(false)
        XCTAssertFalse(model.isTicking)       // backgrounded
        model.setForeground(true)
        XCTAssertTrue(model.isTicking)
        model.setInstagramActive(false)
        XCTAssertFalse(model.isTicking)       // Messages mode
        XCTAssertTrue(model.isUnlocked)       // session itself stays open
        model.stop()
    }

    func testColdLaunchAfterSkippedDaysShowsEarnedNotice() {
        let calendar = Calendar(identifier: .gregorian)
        let today = DayStamp(clock, calendar: calendar)
        let threeDaysBack = today.adding(days: -3, calendar: calendar)
        // Last opened 3 days ago, unused: days -2 and -1 are completed and unpaid.
        BudgetStore(defaults: testDefaults()).save(BudgetState(currentDay: threeDaysBack,
                                                               lastEvaluatedDay: threeDaysBack,
                                                               installDay: threeDaysBack))
        let model = makeModel()
        XCTAssertNotNil(model.earnedNotice)
        XCTAssertEqual(model.earnedNotice, BudgetViewModel.earnedNoticeText(1200))
        XCTAssertEqual(model.vault, 1200, accuracy: 0.0001)
        XCTAssertEqual(model.unusedDaysEarned, 2)

        // A second launch the same day has nothing new to announce.
        XCTAssertNil(makeModel().earnedNotice)
    }

    func testVaultEarnedNoticeAfterRollover() {
        let model = makeModel()
        clock = clock.addingTimeInterval(3 * 86_400)
        model.refresh()
        XCTAssertGreaterThanOrEqual(model.vault, 1200)
        XCTAssertNotNil(model.earnedNotice)
        model.dismissEarnedNotice()
        XCTAssertNil(model.earnedNotice)
    }
}
