//  MessagesView.swift
//  ThinkingOfYou/UI — STUB (Core). The UI agent replaces this file.

import SwiftUI

struct MessagesView: View {
    let people: PeopleViewModel
    let messages: MessagesViewModel
    let snippets: SnippetsStore
    let nudges: NudgesViewModel

    var body: some View {
        @Bindable var people = people
        List {
            if !people.access.canRead {
                Button("Allow Contacts") { Task { await people.requestAccess() } }
            }
            Section("Pinned") {
                ForEach(people.pinnedPeople) { person in
                    PersonRowView(person: person, isPinned: true)
                        .onTapGesture { messages.message(person) }
                }
            }
            Section("Everyone") {
                ForEach(people.otherPeople) { person in
                    PersonRowView(person: person, isPinned: false)
                        .onTapGesture { messages.message(person) }
                        .swipeActions { Button("Pin") { people.togglePin(person) } }
                }
            }
            Section {
                NavigationLink("Quick replies") { SnippetsView(store: snippets) }
                NavigationLink("Nudges") { NudgesView(model: nudges) }
            }
        }
        .searchable(text: $people.searchText)
        .task { await people.onAppear() }
    }
}
