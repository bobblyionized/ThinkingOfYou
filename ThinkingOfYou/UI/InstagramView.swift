//  InstagramView.swift
//  ThinkingOfYou/UI — STUB (Core). The UI agent replaces this file.

import SwiftUI

struct InstagramView: View {
    let model: InstagramViewModel
    let budget: BudgetViewModel

    var body: some View {
        VStack(spacing: 0) {
            BudgetPillView(budget: budget)
            InstagramWebContainer(model: model)
                .overlay(alignment: .bottom) {
                    if let toast = model.toast {
                        Text(toast)
                            .padding()
                            .background(.thinMaterial, in: Capsule())
                            .padding()
                    }
                }
        }
    }
}
