//  NudgesView.swift
//  ThinkingOfYou/UI — STUB (Core). The UI agent replaces this file.

import SwiftUI

struct NudgesView: View {
    let model: NudgesViewModel

    var body: some View {
        List {
            ForEach(model.pending) { nudge in
                VStack(alignment: .leading) {
                    Text("Text \(nudge.name)")
                    Text(NudgesViewModel.scheduleText(for: nudge)).font(.caption)
                }
            }
            .onDelete { offsets in Task { await model.cancel(atOffsets: offsets) } }
        }
        .navigationTitle("Nudges")
        .task { await model.onAppear() }
    }
}
