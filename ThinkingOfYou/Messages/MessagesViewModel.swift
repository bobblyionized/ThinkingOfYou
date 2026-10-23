//  MessagesViewModel.swift
//  ThinkingOfYou/Messages — per-person actions: in-app composer, Messages
//  hand-off, Call, FaceTime and FaceTime Audio. Also opens nudges.
//
//  iMessage history can't be read by third-party apps; this mode is a
//  launcher, not an inbox.

import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class MessagesViewModel {
    // MARK: State

    /// The composer sheet. Bind: `.sheet(item: $messages.composer)`.
    var composer: ComposeDraft? = nil
    /// How the last composer sheet ended (for a "Sent" toast etc.).
    private(set) var lastOutcome: ComposeOutcome? = nil
    /// User-facing problem ("Ada has no phone number"). Bind to an alert and
    /// set back to nil (or call `dismissAlert()`).
    var alertMessage: String? = nil

    /// Whether the in-app composer works on this device.
    var canSendText: Bool { MessageComposer.canSendText() }

    let people: PeopleViewModel
    private let urlOpener: ((URL) -> Void)?

    /// `openURL` overrides UIApplication.shared.open (tests/previews).
    init(people: PeopleViewModel, openURL: ((URL) -> Void)? = nil) {
        self.people = people
        self.urlOpener = openURL
    }

    // MARK: Actions

    /// Runs `action` for `person`. `body` pre-fills Message / Open in Messages.
    func perform(_ action: PersonAction, for person: Person, body: String = "") {
        switch action {
        case .message: message(person, body: body)
        case .openInMessages: openInMessages(person, body: body)
        case .call: call(person)
        case .faceTime: faceTime(person)
        case .faceTimeAudio: faceTimeAudio(person)
        }
    }

    /// Whether `action` can work for `person` (has a number / address).
    func isAvailable(_ action: PersonAction, for person: Person) -> Bool {
        switch action {
        case .message, .openInMessages, .faceTime, .faceTimeAudio: return person.canMessage
        case .call: return person.canCall
        }
    }

    /// In-app composer to the person's best address (falls back to the Messages app).
    func message(_ person: Person, body: String = "") {
        guard let address = person.messageAddress else {
            alertMessage = "\(person.displayName) has no phone number or email."
            return
        }
        compose(to: [address], body: body, personName: person.displayName, contactID: person.id)
    }

    /// In-app composer to one specific number/email of the person.
    func message(_ person: Person, handle: ContactHandle, body: String = "") {
        compose(to: [handle.address], body: body, personName: person.displayName, contactID: person.id)
    }

    /// Composer for arbitrary recipients (falls back to the Messages app).
    func compose(to recipients: [String], body: String = "", personName: String? = nil, contactID: String? = nil) {
        let cleaned = recipients.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            alertMessage = "There's no one to message."
            return
        }
        if canSendText {
            composer = ComposeDraft(recipients: cleaned, body: body, personName: personName, contactID: contactID)
        } else if let url = ContactActions.smsURL(addresses: cleaned, body: body) {
            open(url)
        }
    }

    func openInMessages(_ person: Person, body: String = "") {
        guard let url = ContactActions.url(for: .openInMessages, person: person, body: body) else {
            alertMessage = "\(person.displayName) has no phone number or email."
            return
        }
        open(url)
    }

    func call(_ person: Person) {
        guard let url = ContactActions.url(for: .call, person: person) else {
            alertMessage = "\(person.displayName) has no phone number."
            return
        }
        open(url)
    }

    func faceTime(_ person: Person) {
        guard let url = ContactActions.url(for: .faceTime, person: person) else {
            alertMessage = "\(person.displayName) has no phone number or email for FaceTime."
            return
        }
        open(url)
    }

    func faceTimeAudio(_ person: Person) {
        guard let url = ContactActions.url(for: .faceTimeAudio, person: person) else {
            alertMessage = "\(person.displayName) has no phone number or email for FaceTime."
            return
        }
        open(url)
    }

    /// Call from MessageComposer's onFinish: closes the sheet.
    func composerFinished(_ outcome: ComposeOutcome) {
        lastOutcome = outcome
        composer = nil
    }

    func dismissAlert() {
        alertMessage = nil
    }

    /// A tapped nudge notification: open the composer pre-filled.
    func openNudge(_ route: NudgeRoute) async {
        await people.loadIfNeeded()
        if let id = route.contactID, let person = people.person(withID: id) {
            message(person, body: route.body)
            return
        }
        if let address = route.address, !address.isEmpty {
            compose(to: [address], body: route.body, personName: route.name, contactID: route.contactID)
            return
        }
        alertMessage = "Couldn't find \(route.name) in your contacts."
    }

    // MARK: Internals

    private func open(_ url: URL) {
        if let urlOpener {
            urlOpener(url)
        } else {
            UIApplication.shared.open(url)
        }
    }
}
