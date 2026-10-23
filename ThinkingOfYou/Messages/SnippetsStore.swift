//  SnippetsStore.swift
//  ThinkingOfYou/Messages — editable quick-reply templates, persisted as JSON
//  in UserDefaults. Defaults are seeded on first launch only.

import Foundation
import Observation
import SwiftUI // Array.move(fromOffsets:toOffset:) / remove(atOffsets:)

struct Snippet: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

@Observable
@MainActor
final class SnippetsStore {
    static let defaultsKey = "snippets.v1"

    static let defaultTexts: [String] = [
        "Thinking of you ❤️",
        "How are you doing?",
        "Miss you! Free to catch up this week?",
        "Just saw something that reminded me of you",
        "Proud of you!",
        "Good luck today, you've got this",
        "Can I call you later?",
        "Happy birthday! 🎉",
    ]

    /// The templates, in the user's order.
    private(set) var snippets: [Snippet]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([Snippet].self, from: data) {
            self.snippets = saved
        } else {
            self.snippets = Self.defaultTexts.map { Snippet(text: $0) }
        }
    }

    func snippet(withID id: UUID) -> Snippet? {
        snippets.first { $0.id == id }
    }

    /// Adds a template at the end. Ignores blank text. Returns the new snippet.
    @discardableResult
    func add(_ text: String) -> Snippet? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let snippet = Snippet(text: trimmed)
        snippets.append(snippet)
        save()
        return snippet
    }

    /// Replaces a template's text. Blank text deletes it.
    func update(_ id: UUID, text: String) {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            snippets.remove(at: index)
        } else {
            snippets[index].text = trimmed
        }
        save()
    }

    func delete(_ id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    /// For `.onDelete`.
    func delete(atOffsets offsets: IndexSet) {
        snippets.remove(atOffsets: offsets)
        save()
    }

    /// For `.onMove`.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        snippets.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func resetToDefaults() {
        snippets = Self.defaultTexts.map { Snippet(text: $0) }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
