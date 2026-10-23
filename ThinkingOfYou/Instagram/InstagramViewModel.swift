//  InstagramViewModel.swift
//  ThinkingOfYou/Instagram — state of the caged Instagram web view.
//  Owns the long-lived InstagramWebCoordinator (and so the WKWebView), which
//  survives mode switches; InstagramWebContainer just hosts its view.

import Foundation
import Observation
import WebKit

@Observable
@MainActor
final class InstagramViewModel {
    static let detectedUsernameKey = "instagram.ownUsername.detected"
    static let manualUsernameKey = "instagram.ownUsername.manual"

    // MARK: State (read-only for views unless noted)

    private(set) var isLoading = false
    /// 0...1 page-load progress.
    private(set) var progress: Double = 0
    private(set) var canGoBack = false
    private(set) var currentURL: URL? = nil
    /// Unread DM threads, polled by Cage.js every minute.
    private(set) var unreadCount = 0
    /// Message of the last failed load; nil when fine. `reload()` clears it.
    private(set) var loadError: String? = nil
    /// Short message for the UI to show (blocked page, etc.). Auto-clears
    /// after ~2.6 s; views may also call `dismissToast()`.
    private(set) var toast: String? = nil
    /// Mirrors BudgetViewModel.isUnlocked (set by AppEnvironment).
    private(set) var isUnlocked = false
    /// Username found automatically by Cage.js (persisted).
    private(set) var detectedUsername: String? = nil
    /// Username typed in Settings (persisted). Wins over `detectedUsername`.
    private(set) var manualUsername: String? = nil

    // MARK: Derived

    /// The account whose own profile is blocked while locked.
    var ownUsername: String? { manualUsername ?? detectedUsername }
    var isUsingManualUsername: Bool { manualUsername != nil }
    var cageRules: CageRules { CageRules(ownUsername: ownUsername) }
    var currentPath: String { currentURL.map(CageRules.pathWithSlash) ?? CageRules.inboxPath }
    var isAtInbox: Bool {
        let parts = CageRules.segments(of: currentPath)
        return parts.count == 2 && parts[0] == "direct" && parts[1] == "inbox"
    }
    var isOnReel: Bool { CageRules.reelCode(inPath: currentPath) != nil }
    /// True once the web view has been created (first time the container shows).
    var hasWebView: Bool { coordinator != nil }

    // MARK: Internals

    @ObservationIgnored private var coordinator: InstagramWebCoordinator? = nil
    private let defaults: UserDefaults
    @ObservationIgnored private var toastTask: Task<Void, Never>? = nil

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.detectedUsername = CageRules.sanitizeUsername(defaults.string(forKey: Self.detectedUsernameKey))
        self.manualUsername = CageRules.sanitizeUsername(defaults.string(forKey: Self.manualUsernameKey))
    }

    /// The web view's coordinator, created (and loading the inbox) on first use.
    var webCoordinator: InstagramWebCoordinator {
        if let coordinator { return coordinator }
        let created = InstagramWebCoordinator(model: self)
        coordinator = created
        return created
    }

    // MARK: Actions

    func reload() {
        loadError = nil
        if let coordinator {
            coordinator.reload()
        } else {
            _ = webCoordinator
        }
    }

    func goInbox() {
        coordinator?.load(CageRules.inboxURL)
    }

    func goActivity() {
        webCoordinator.load(CageRules.activityURL)
    }

    func goBack() {
        coordinator?.goBack()
    }

    /// Called by AppEnvironment whenever the budget locks or unlocks.
    func setUnlocked(_ unlocked: Bool) {
        guard unlocked != isUnlocked else { return }
        isUnlocked = unlocked
        coordinator?.pushState()
    }

    /// Sets the manual "my username" fallback. Empty/nil clears it. Returns
    /// false (and changes nothing) when the text isn't a valid handle.
    @discardableResult
    func setManualUsername(_ raw: String?) -> Bool {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            clearManualUsername()
            return true
        }
        guard let name = CageRules.sanitizeUsername(trimmed) else { return false }
        manualUsername = name
        defaults.set(name, forKey: Self.manualUsernameKey)
        coordinator?.pushState()
        return true
    }

    func clearManualUsername() {
        manualUsername = nil
        defaults.removeObject(forKey: Self.manualUsernameKey)
        coordinator?.pushState()
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    /// Signs out of Instagram by wiping the web view's cookies and storage.
    func signOut() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: Date.distantPast)
        detectedUsername = nil
        defaults.removeObject(forKey: Self.detectedUsernameKey)
        unreadCount = 0
        coordinator?.pushState()
        coordinator?.load(CageRules.inboxURL)
    }

    // MARK: Coordinator callbacks

    func webViewDidUpdate(isLoading: Bool, url: URL?, canGoBack: Bool, progress: Double) {
        if self.isLoading != isLoading { self.isLoading = isLoading }
        if self.currentURL != url, url != nil { self.currentURL = url }
        if self.canGoBack != canGoBack { self.canGoBack = canGoBack }
        if abs(self.progress - progress) > 0.01 || progress >= 1 { self.progress = progress }
        if !isLoading, loadError != nil, url != nil, progress >= 1 { loadError = nil }
    }

    func didDetectUsername(_ raw: String?) {
        guard let name = CageRules.sanitizeUsername(raw), name != detectedUsername else { return }
        detectedUsername = name
        defaults.set(name, forKey: Self.detectedUsernameKey)
        coordinator?.pushState()
    }

    func didBlock(reason: String) {
        showToast(Self.toastText(forBlockedReason: reason))
    }

    func didUpdateUnread(_ count: Int) {
        let clamped = max(0, count)
        if unreadCount != clamped { unreadCount = clamped }
    }

    func didFailLoading(_ message: String) {
        loadError = message
    }

    static func toastText(forBlockedReason reason: String) -> String {
        if reason == CageRules.Block.nextReel.reason {
            return "One reel at a time while you're locked"
        }
        return "\(reason) is locked. Start a scroll session to open it."
    }
}
