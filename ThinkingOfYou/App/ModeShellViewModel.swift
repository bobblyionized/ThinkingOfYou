//  ModeShellViewModel.swift
//  ThinkingOfYou/App — which of the two modes is showing. Persisted in
//  UserDefaults "lastMode" and restored on launch.

import Foundation
import Observation

enum AppMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case instagram
    case messages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instagram: return "Instagram"
        case .messages: return "Messages"
        }
    }

    /// SF Symbol name.
    var systemImage: String {
        switch self {
        case .instagram: return "camera.circle.fill"
        case .messages: return "message.fill"
        }
    }

    var other: AppMode { self == .instagram ? .messages : .instagram }
}

@Observable
@MainActor
final class ModeShellViewModel {
    static let defaultsKey = "lastMode"
    static let defaultMode: AppMode = .instagram

    private var storedMode: AppMode

    /// The current mode. Settable, so `$shell.mode` works for a
    /// `TabView(selection:)` / `Picker`; setting it is the same as `select(_:)`.
    var mode: AppMode {
        get { storedMode }
        set { select(newValue) }
    }

    /// Called after every change (AppEnvironment wires the budget timer to it).
    @ObservationIgnored var onModeChange: (@MainActor (AppMode) -> Void)? = nil

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.storedMode = defaults.string(forKey: Self.defaultsKey).flatMap(AppMode.init(rawValue:)) ?? Self.defaultMode
    }

    /// Flips between Instagram and Messages.
    func switchMode() {
        select(storedMode.other)
    }

    func select(_ newMode: AppMode) {
        guard newMode != storedMode else { return }
        storedMode = newMode
        defaults.set(newMode.rawValue, forKey: Self.defaultsKey)
        onModeChange?(newMode)
    }
}
