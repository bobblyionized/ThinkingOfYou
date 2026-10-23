//  SnippetsView.swift
//  ThinkingOfYou/UI — STUB (Core). The UI agent replaces this file.

import SwiftUI

struct SnippetsView: View {
    let store: SnippetsStore
    var onPick: ((Snippet) -> Void)? = nil

    var body: some View {
        List {
            ForEach(store.snippets) { snippet in
                Button(snippet.text) { onPick?(snippet) }
            }
            .onDelete { store.delete(atOffsets: $0) }
            .onMove { store.move(fromOffsets: $0, toOffset: $1) }
        }
        .navigationTitle("Quick replies")
    }
}
