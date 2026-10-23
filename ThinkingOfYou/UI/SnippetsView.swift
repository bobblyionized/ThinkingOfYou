//  SnippetsView.swift
//  ThinkingOfYou/UI — quick replies. Without `onPick` it's an editor (tap to
//  edit, swipe to delete, drag to reorder, add new); with `onPick` tapping a
//  reply hands it back to the caller.

import SwiftUI

struct SnippetsView: View {
    let store: SnippetsStore
    var onPick: ((Snippet) -> Void)? = nil

    @State private var newText = ""
    @State private var editing: Snippet?
    @State private var editText = ""
    @State private var confirmingReset = false
    @State private var addedCount = 0
    @FocusState private var addFocused: Bool

    var body: some View {
        List {
            Section {
                ForEach(store.snippets) { snippet in
                    Button {
                        if let onPick {
                            onPick(snippet)
                        } else {
                            editText = snippet.text
                            editing = snippet
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                            Image(systemName: "text.bubble")
                                .font(.footnote)
                                .foregroundStyle(Theme.rose)
                                .accessibilityHidden(true)
                            Text(snippet.text)
                                .font(.body)
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, Space.xxs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(onPick == nil ? "Edits this reply" : "Uses this reply")
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.delete(snippet.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        if onPick != nil {
                            Button {
                                editText = snippet.text
                                editing = snippet
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(Theme.wine)
                        }
                    }
                }
                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                .listRowBackground(Theme.card)
            } header: {
                SectionHeading(title: "Your replies",
                               detail: store.snippets.isEmpty ? nil : "\(store.snippets.count)")
            } footer: {
                Text(onPick == nil
                     ? "Touch and hold Message on anyone to send one of these. Tap a reply to edit it."
                     : "Tap a reply to use it.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
            }

            Section {
                HStack(spacing: Space.s) {
                    TextField("Write a new reply", text: $newText, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($addFocused)
                        .submitLabel(.done)
                        .foregroundStyle(Theme.ink)
                    Button {
                        add()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(CircleIconButtonStyle(diameter: 34))
                    .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add reply")
                }
                .listRowBackground(Theme.card)
            } header: {
                SectionHeading(title: "Add one")
            }

            Section {
                Button("Restore the starter replies") {
                    confirmingReset = true
                }
                .foregroundStyle(Theme.wine)
                .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle("Quick replies")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.snippets.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: addedCount)
        .alert("Edit reply", isPresented: Binding(
            get: { editing != nil },
            set: { if !$0 { editing = nil } }
        )) {
            TextField("Reply", text: $editText)
            Button("Save") {
                if let editing {
                    store.update(editing.id, text: editText)
                }
                editing = nil
            }
            Button("Cancel", role: .cancel) { editing = nil }
        } message: {
            Text("Clearing the text deletes the reply.")
        }
        .confirmationDialog("Restore the starter replies?",
                            isPresented: $confirmingReset,
                            titleVisibility: .visible) {
            Button("Restore starter replies", role: .destructive) {
                store.resetToDefaults()
            }
            Button("Keep mine", role: .cancel) {}
        } message: {
            Text("This replaces your current list.")
        }
    }

    private func add() {
        if store.add(newText) != nil {
            newText = ""
            addedCount += 1
        }
    }
}

#Preview {
    NavigationStack {
        SnippetsView(store: AppEnvironment.preview().snippets)
    }
}
