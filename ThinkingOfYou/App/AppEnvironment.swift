//  AppEnvironment.swift
//  ThinkingOfYou/App — builds every long-lived model once and wires them:
//    mode change      -> budget timer only runs in Instagram mode
//    budget lock flip -> cage state pushed to the web view; re-lock -> inbox
//    scene phase      -> budget timer only runs in the foreground
//    nudge tap        -> Messages mode + pre-filled composer
//  Injected at the root with `.environment(env)`.

import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class AppEnvironment {
    let shell: ModeShellViewModel
    let budget: BudgetViewModel
    let instagram: InstagramViewModel
    let people: PeopleViewModel
    let snippets: SnippetsStore
    let nudges: NudgesViewModel
    let messages: MessagesViewModel
    let settings: SettingsViewModel

    init(defaults: UserDefaults = .standard, previewPeople: [Person]? = nil) {
        let shell = ModeShellViewModel(defaults: defaults)
        let budget = BudgetViewModel(defaults: defaults)
        let instagram = InstagramViewModel(defaults: defaults)
        let people = PeopleViewModel(defaults: defaults, preloaded: previewPeople)
        let snippets = SnippetsStore(defaults: defaults)
        let nudges = NudgesViewModel()
        let messages = MessagesViewModel(people: people)
        let settings = SettingsViewModel(instagram: instagram, budget: budget, people: people,
                                         nudges: nudges, snippets: snippets)
        self.shell = shell
        self.budget = budget
        self.instagram = instagram
        self.people = people
        self.snippets = snippets
        self.nudges = nudges
        self.messages = messages
        self.settings = settings

        shell.onModeChange = { [weak self] mode in
            self?.modeChanged(to: mode)
        }
        budget.onLockChange = { [weak self] unlocked in
            self?.lockChanged(unlocked: unlocked)
        }
        budget.setInstagramActive(shell.mode == .instagram)
        instagram.setUnlocked(budget.isUnlocked)
    }

    /// Call once from the root `.task`.
    func launch() async {
        budget.refresh()
        await nudges.refresh()
        if people.access.canRead {
            await people.reload()
        }
    }

    /// Wire to `.onChange(of: scenePhase, initial: true)`.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            budget.setForeground(true)
            settings.refreshInstagramAppCheck()
            Task { await nudges.refresh() }
        case .inactive, .background:
            budget.setForeground(false)
        @unknown default:
            budget.setForeground(false)
        }
    }

    /// A tapped "Text <name>" notification.
    func handleNudge(_ route: NudgeRoute) {
        shell.select(.messages)
        Task { await messages.openNudge(route) }
    }

    // MARK: Wiring

    private func modeChanged(to mode: AppMode) {
        budget.setInstagramActive(mode == .instagram)
    }

    private func lockChanged(unlocked: Bool) {
        instagram.setUnlocked(unlocked)
        if !unlocked {
            instagram.goInbox()
        }
    }

    // MARK: Previews

    /// In-memory defaults and a few sample people; never touches Contacts.
    static func preview(mode: AppMode = .messages) -> AppEnvironment {
        let suite = "preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.set(mode.rawValue, forKey: ModeShellViewModel.defaultsKey)
        return AppEnvironment(defaults: defaults, previewPeople: Person.samples)
    }
}

extension Person {
    /// Sample people for previews and tests.
    static let samples: [Person] = [
        Person(id: "sample-ada", givenName: "Ada", familyName: "Lovelace",
               phones: [ContactHandle(kind: .phone, label: "mobile", value: "+1 (555) 010-1815")],
               emails: [ContactHandle(kind: .email, label: "home", value: "ada@example.com")]),
        Person(id: "sample-grace", givenName: "Grace", familyName: "Hopper", nickname: "Amazing Grace",
               phones: [ContactHandle(kind: .phone, label: "mobile", value: "+1 555 010 1906")]),
        Person(id: "sample-mum", givenName: "Mum",
               phones: [ContactHandle(kind: .phone, label: "home", value: "555-0123")]),
        Person(id: "sample-alan", givenName: "Alan", familyName: "Turing",
               emails: [ContactHandle(kind: .email, label: "work", value: "alan@example.com")]),
    ]
}
