//  PeopleViewModel.swift
//  ThinkingOfYou/Messages — contacts access, the people list, search and pins.

import Contacts
import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class PeopleViewModel {
    static let pinnedKey = "people.pinnedIDs"

    // MARK: State

    private(set) var access: ContactsAccess
    /// All contacts, sorted by display name.
    private(set) var people: [Person] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String? = nil
    /// Pinned contact identifiers, in the user's order.
    private(set) var pinnedIDs: [String]
    /// Bind to `.searchable(text: $people.searchText)`.
    var searchText: String = ""

    // MARK: Derived

    /// Pinned people that still exist, in pin order (ignores search).
    var pinnedPeople: [Person] {
        let byID = peopleByID
        return pinnedIDs.compactMap { byID[$0] }
    }

    /// Everyone matching `searchText` (pinned included).
    var filteredPeople: [Person] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return people }
        return people.filter { $0.matches(query) }
    }

    /// The non-pinned people matching `searchText` (for "All contacts" under a
    /// Pinned section).
    var otherPeople: [Person] {
        let pinned = Set(pinnedIDs)
        return filteredPeople.filter { !pinned.contains($0.id) }
    }

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private let defaults: UserDefaults
    private var peopleByID: [String: Person] = [:]
    @ObservationIgnored private var changeObserver: NSObjectProtocol? = nil
    /// The contacts fetch in flight, shared by every caller that needs it.
    @ObservationIgnored private var loadTask: Task<Void, Never>? = nil
    private let isPreview: Bool

    init(defaults: UserDefaults = .standard, preloaded: [Person]? = nil) {
        self.defaults = defaults
        self.pinnedIDs = defaults.stringArray(forKey: Self.pinnedKey) ?? []
        self.isPreview = preloaded != nil
        if let preloaded {
            // Previews/tests: skip Contacts entirely.
            self.access = .authorized
            self.people = Self.sorted(preloaded)
            self.peopleByID = Dictionary(preloaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.hasLoaded = true
        } else {
            self.access = ContactsService.currentAccess()
        }
    }

    // MARK: Actions

    /// Call from `.task`: loads contacts if access was already granted.
    func onAppear() async {
        startObservingChanges()
        refreshAccess()
        if access.canRead, !hasLoaded {
            await reload()
        }
    }

    /// Asks for Contacts access (system prompt the first time), then loads.
    func requestAccess() async {
        if access == .notDetermined {
            _ = await ContactsService.requestAccess()
        }
        refreshAccess()
        if access.canRead {
            await reload()
        }
    }

    /// Loads contacts once if possible (used before opening a nudge). If a
    /// load is already running, waits for it instead of returning early.
    func loadIfNeeded() async {
        if let loadTask {
            await loadTask.value
            return
        }
        refreshAccess()
        guard access.canRead, !hasLoaded else { return }
        await reload()
    }

    /// Fetches contacts. Concurrent calls join the fetch already in flight.
    func reload() async {
        refreshAccess()
        guard !isPreview else { return }
        guard access.canRead else {
            people = []
            peopleByID = [:]
            return
        }
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.fetchContacts()
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func fetchContacts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await ContactsService.fetchAll()
            people = Self.sorted(fetched)
            peopleByID = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAccess() {
        guard !isPreview else { return }
        let current = ContactsService.currentAccess()
        if current != access { access = current }
    }

    func person(withID id: String) -> Person? {
        peopleByID[id]
    }

    func isPinned(_ person: Person) -> Bool {
        pinnedIDs.contains(person.id)
    }

    func togglePin(_ person: Person) {
        if let index = pinnedIDs.firstIndex(of: person.id) {
            pinnedIDs.remove(at: index)
        } else {
            pinnedIDs.append(person.id)
        }
        savePins()
    }

    func pin(_ person: Person) {
        guard !pinnedIDs.contains(person.id) else { return }
        pinnedIDs.append(person.id)
        savePins()
    }

    func unpin(_ person: Person) {
        pinnedIDs.removeAll { $0 == person.id }
        savePins()
    }

    /// For `.onMove` on the Pinned section (offsets index `pinnedPeople`).
    func movePinned(fromOffsets source: IndexSet, toOffset destination: Int) {
        var visible = pinnedPeople.map(\.id)
        let moving = source.sorted().compactMap { visible.indices.contains($0) ? visible[$0] : nil }
        guard !moving.isEmpty else { return }
        let insertAt = destination - source.filter { $0 < destination }.count
        visible.removeAll { moving.contains($0) }
        visible.insert(contentsOf: moving, at: max(0, min(insertAt, visible.count)))
        // Keep pins for contacts that aren't loaded (e.g. no access yet) at the end.
        let hidden = pinnedIDs.filter { !visible.contains($0) && !moving.contains($0) }
        pinnedIDs = visible + hidden
        savePins()
    }

    /// For `.onDelete` on the Pinned section (offsets index `pinnedPeople`).
    func unpin(atOffsets offsets: IndexSet) {
        let visible = pinnedPeople
        let ids = offsets.compactMap { visible.indices.contains($0) ? visible[$0].id : nil }
        pinnedIDs.removeAll { ids.contains($0) }
        savePins()
    }

    /// Opens this app's page in the Settings app (to grant Contacts access).
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Internals

    private func savePins() {
        defaults.set(pinnedIDs, forKey: Self.pinnedKey)
    }

    private static func sorted(_ list: [Person]) -> [Person] {
        list.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func startObservingChanges() {
        guard changeObserver == nil else { return }
        changeObserver = NotificationCenter.default.addObserver(forName: .CNContactStoreDidChange,
                                                                object: nil,
                                                                queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.access.canRead else { return }
                await self.reload()
            }
        }
    }
}
