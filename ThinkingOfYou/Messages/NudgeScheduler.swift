//  NudgeScheduler.swift
//  ThinkingOfYou/Messages — "Text <name>" reminders as local notifications.
//  userInfo carries the contact identifier, name, address and message body;
//  tapping one opens the app in Messages mode with the composer pre-filled
//  (AppDelegate -> AppEnvironment.handleNudge).

import Foundation
import UserNotifications

enum NudgeRepeat: String, CaseIterable, Identifiable, Codable, Sendable {
    case never
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return "Once"
        case .daily: return "Every day"
        case .weekly: return "Every week"
        }
    }
}

/// A pending nudge, read back from the notification center.
struct Nudge: Identifiable, Hashable, Sendable {
    /// The notification request identifier.
    let id: String
    let contactID: String?
    let name: String
    let address: String?
    let body: String
    let repeats: NudgeRepeat
    /// When it fires next (nil if the system can't tell).
    let nextFireDate: Date?
}

/// What a tapped nudge asks the app to do.
struct NudgeRoute: Equatable, Sendable {
    var contactID: String?
    var name: String
    var address: String?
    var body: String
}

enum NotificationAccess: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

enum NudgeError: LocalizedError, Equatable {
    case dateInPast
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .dateInPast: return "Pick a time in the future."
        case .notAuthorized: return "Allow notifications for Thinking Of You in Settings to get nudges."
        }
    }
}

/// Stateless service over UNUserNotificationCenter.current().
struct NudgeScheduler: Sendable {
    static let identifierPrefix = "toy.nudge."
    static let categoryIdentifier = "toy.nudge"
    static let kindValue = "nudge"

    enum Key {
        static let kind = "toyKind"
        static let contactID = "contactID"
        static let name = "name"
        static let address = "address"
        static let body = "body"
        static let repeats = "repeats"
    }

    init() {}

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    func authorization() async -> NotificationAccess {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .authorized // authorized, provisional, ephemeral
        }
    }

    /// Prompts the first time. Returns whether nudges can be delivered.
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Schedules "Text <name>" at `date` (time of day/week for repeats).
    @discardableResult
    func schedule(name: String,
                  contactID: String?,
                  address: String?,
                  body: String,
                  at date: Date,
                  repeats: NudgeRepeat = .never,
                  now: Date = Date(),
                  calendar: Calendar = .current) async throws -> Nudge {
        if repeats == .never, date <= now { throw NudgeError.dateInPast }
        var access = await authorization()
        if access == .notDetermined {
            access = await requestAuthorization() ? .authorized : .denied
        }
        guard access == .authorized else { throw NudgeError.notAuthorized }

        let identifier = Self.identifierPrefix + UUID().uuidString
        let content = Self.makeContent(name: name, contactID: contactID, address: address, body: body, repeats: repeats)
        let trigger = Self.makeTrigger(date: date, repeats: repeats, calendar: calendar)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
        return Nudge(id: identifier, contactID: contactID, name: name, address: address, body: body,
                     repeats: repeats, nextFireDate: trigger.nextTriggerDate())
    }

    /// Pending nudges, soonest first.
    func pending() async -> [Nudge] {
        let requests = await center.pendingNotificationRequests()
        return requests.compactMap(Self.nudge(from:)).sorted {
            ($0.nextFireDate ?? .distantFuture) < ($1.nextFireDate ?? .distantFuture)
        }
    }

    func cancel(ids: [String]) {
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    // MARK: Pure helpers (tested)

    static func makeContent(name: String, contactID: String?, address: String?, body: String,
                            repeats: NudgeRepeat) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Text \(name)"
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = trimmed.isEmpty ? "Tap to send them a message." : "“\(trimmed)”"
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        var info: [String: Any] = [
            Key.kind: kindValue,
            Key.name: name,
            Key.body: body,
            Key.repeats: repeats.rawValue,
        ]
        if let contactID { info[Key.contactID] = contactID }
        if let address { info[Key.address] = address }
        content.userInfo = info
        return content
    }

    static func makeTrigger(date: Date, repeats: NudgeRepeat, calendar: Calendar = .current) -> UNCalendarNotificationTrigger {
        let components: DateComponents
        switch repeats {
        case .never:
            components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        case .daily:
            components = calendar.dateComponents([.hour, .minute], from: date)
        case .weekly:
            components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        }
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats != .never)
    }

    /// Reads a nudge's route out of a notification's userInfo (nil if it isn't one).
    static func route(from userInfo: [AnyHashable: Any]) -> NudgeRoute? {
        guard (userInfo[Key.kind] as? String) == kindValue else { return nil }
        return NudgeRoute(contactID: userInfo[Key.contactID] as? String,
                          name: (userInfo[Key.name] as? String) ?? "them",
                          address: userInfo[Key.address] as? String,
                          body: (userInfo[Key.body] as? String) ?? "")
    }

    static func nudge(from request: UNNotificationRequest) -> Nudge? {
        guard request.identifier.hasPrefix(identifierPrefix),
              let route = route(from: request.content.userInfo) else { return nil }
        let repeats = (request.content.userInfo[Key.repeats] as? String).flatMap(NudgeRepeat.init(rawValue:)) ?? .never
        let next = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
        return Nudge(id: request.identifier, contactID: route.contactID, name: route.name,
                     address: route.address, body: route.body, repeats: repeats, nextFireDate: next)
    }
}
