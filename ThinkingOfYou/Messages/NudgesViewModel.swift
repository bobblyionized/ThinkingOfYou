//  NudgesViewModel.swift
//  ThinkingOfYou/Messages — schedule, list and cancel "Text <name>" nudges.

import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class NudgesViewModel {
    // MARK: State

    /// Pending nudges, soonest first.
    private(set) var pending: [Nudge] = []
    private(set) var access: NotificationAccess = .notDetermined
    private(set) var isLoading = false
    /// User-facing error from the last schedule attempt; set to nil to dismiss.
    var errorMessage: String? = nil

    // Draft for a "new nudge" form (bind these).
    var draftDate: Date
    var draftRepeat: NudgeRepeat = .never
    var draftBody: String = ""

    private let scheduler: NudgeScheduler
    private let now: () -> Date

    init(scheduler: NudgeScheduler = NudgeScheduler(), now: @escaping () -> Date = { Date() }) {
        self.scheduler = scheduler
        self.now = now
        self.draftDate = Self.suggestedDate(after: now())
    }

    // MARK: Actions

    /// Call from `.task`.
    func onAppear() async {
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        access = await scheduler.authorization()
        pending = await scheduler.pending()
    }

    @discardableResult
    func requestAccess() async -> Bool {
        let granted = await scheduler.requestAuthorization()
        access = await scheduler.authorization()
        return granted
    }

    /// Schedules a nudge for `person`. Nil arguments use the draft fields.
    /// Returns true on success; on failure `errorMessage` says why.
    @discardableResult
    func schedule(for person: Person, body: String? = nil, at date: Date? = nil, repeats: NudgeRepeat? = nil) async -> Bool {
        do {
            try await scheduler.schedule(name: person.shortName,
                                         contactID: person.id,
                                         address: person.messageAddress,
                                         body: body ?? draftBody,
                                         at: date ?? draftDate,
                                         repeats: repeats ?? draftRepeat,
                                         now: now())
            errorMessage = nil
            resetDraft()
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            access = await scheduler.authorization()
            return false
        }
    }

    func cancel(_ nudge: Nudge) async {
        scheduler.cancel(ids: [nudge.id])
        pending.removeAll { $0.id == nudge.id }
        await refresh()
    }

    /// For `.onDelete` over `pending` (or over `nudges(for:)` when you pass that list).
    func cancel(atOffsets offsets: IndexSet, in list: [Nudge]? = nil) async {
        let source = list ?? pending
        let ids = offsets.compactMap { source.indices.contains($0) ? source[$0].id : nil }
        scheduler.cancel(ids: ids)
        pending.removeAll { ids.contains($0.id) }
        await refresh()
    }

    func cancelAll(for person: Person) async {
        let ids = nudges(for: person.id).map(\.id)
        scheduler.cancel(ids: ids)
        pending.removeAll { ids.contains($0.id) }
        await refresh()
    }

    func nudges(for contactID: String) -> [Nudge] {
        pending.filter { $0.contactID == contactID }
    }

    func resetDraft() {
        draftDate = Self.suggestedDate(after: now())
        draftRepeat = .never
        draftBody = ""
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Formatting

    /// "Tomorrow, 7:00 PM" / "Every day, 9:00 AM" / "Every Monday, 6:30 PM".
    static func scheduleText(for nudge: Nudge, calendar: Calendar = .current) -> String {
        guard let date = nudge.nextFireDate else { return nudge.repeats.title }
        let time = date.formatted(date: .omitted, time: .shortened)
        switch nudge.repeats {
        case .daily:
            return "Every day, \(time)"
        case .weekly:
            let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: date) - 1]
            return "Every \(weekday), \(time)"
        case .never:
            if calendar.isDateInToday(date) { return "Today, \(time)" }
            if calendar.isDateInTomorrow(date) { return "Tomorrow, \(time)" }
            return date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    /// The next whole hour at least 30 minutes away.
    static func suggestedDate(after date: Date, calendar: Calendar = .current) -> Date {
        let later = date.addingTimeInterval(30 * 60)
        let hourStart = calendar.dateInterval(of: .hour, for: later)?.start ?? later
        return calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? later
    }
}
