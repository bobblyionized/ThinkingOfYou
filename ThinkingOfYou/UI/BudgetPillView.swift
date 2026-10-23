//  BudgetPillView.swift
//  ThinkingOfYou/UI — STUB (Core). The UI agent replaces this file.

import SwiftUI

struct BudgetPillView: View {
    let budget: BudgetViewModel

    var body: some View {
        HStack {
            Text(budget.statusText).font(.footnote)
            Spacer()
            if budget.isUnlocked {
                Button("Stop") { budget.stop() }
            } else {
                Button("Scroll") { budget.start() }.disabled(!budget.canStart)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
