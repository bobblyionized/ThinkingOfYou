//  SettingsViewModel.swift
//  ThinkingOfYou/App — the settings screen: manual "my username" fallback,
//  Instagram sign-out, permission shortcuts, and the platform-limit notes.

import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class SettingsViewModel {
    // MARK: State

    /// Text field for the manual username. Bind: `TextField("username", text: $settings.usernameDraft)`.
    var usernameDraft: String = ""
    /// Validation message after `saveUsername()`; nil when fine.
    private(set) var usernameError: String? = nil
    /// True when the real Instagram app is still installed (the cage only
    /// applies inside this app, so the UI should nudge to offload it).
    private(set) var isInstagramAppInstalled = false
    private(set) var isSigningOut = false

    let instagram: InstagramViewModel
    let budget: BudgetViewModel
    let people: PeopleViewModel
    let nudges: NudgesViewModel
    let snippets: SnippetsStore

    // MARK: Derived

    var detectedUsername: String? { instagram.detectedUsername }
    var manualUsername: String? { instagram.manualUsername }
    /// The username whose own profile is blocked, with "@".
    var effectiveUsernameText: String {
        instagram.ownUsername.map { "@\($0)" } ?? "Not detected yet"
    }
    var contactsAccess: ContactsAccess { people.access }
    var notificationAccess: NotificationAccess { nudges.access }

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    /// Plain-language rules for the budget section.
    var budgetRulesText: String {
        "You get \(BudgetFormat.short(budget.dailyAllowance)) of feed and Reels scrolling a day, reset at midnight. "
            + "Every day you don't scroll at all banks \(BudgetFormat.short(ScrollBudgetEngine.defaultVaultReward)) in the vault. "
            + "Messages, notes, stories, profiles and single posts or reels friends send you are always open."
    }

    /// The honest limits, for an "About" section.
    static let platformLimits: [String] = [
        "iOS doesn't let any third-party app read your iMessages, so Messages mode is a launcher: pinned people, quick replies and reminders.",
        "The scroll limit only applies inside Thinking Of You. Delete or offload the real Instagram app so it can't be skipped.",
        "Instagram changes its website often; if something slips through the cage, the native backstop still blocks full page loads.",
    ]

    init(instagram: InstagramViewModel,
         budget: BudgetViewModel,
         people: PeopleViewModel,
         nudges: NudgesViewModel,
         snippets: SnippetsStore) {
        self.instagram = instagram
        self.budget = budget
        self.people = people
        self.nudges = nudges
        self.snippets = snippets
    }

    // MARK: Actions

    /// Call from `.onAppear` / `.task`.
    func onAppear() {
        usernameDraft = instagram.manualUsername ?? ""
        usernameError = nil
        refreshInstagramAppCheck()
    }

    /// Saves `usernameDraft` as the manual username (empty clears it).
    @discardableResult
    func saveUsername() -> Bool {
        if instagram.setManualUsername(usernameDraft) {
            usernameError = nil
            usernameDraft = instagram.manualUsername ?? ""
            return true
        }
        usernameError = "That doesn't look like an Instagram username."
        return false
    }

    /// Drops the manual username and goes back to the detected one.
    func useDetectedUsername() {
        instagram.clearManualUsername()
        usernameDraft = ""
        usernameError = nil
    }

    func refreshInstagramAppCheck() {
        guard let url = URL(string: "instagram://app") else { return }
        isInstagramAppInstalled = UIApplication.shared.canOpenURL(url)
    }

    func signOutOfInstagram() async {
        isSigningOut = true
        await instagram.signOut()
        isSigningOut = false
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
