//  RootView.swift
//  ThinkingOfYou/UI — STUB (Core). The UI agent replaces this file.
//  Must stay `RootView()` with no parameters: ThinkingOfYouApp creates it and
//  injects `AppEnvironment` via `.environment(env)`.

import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showingSettings = false

    var body: some View {
        @Bindable var shell = env.shell
        @Bindable var messages = env.messages
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $shell.mode) {
                    ForEach(AppMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch shell.mode {
                case .instagram:
                    InstagramView(model: env.instagram, budget: env.budget)
                case .messages:
                    MessagesView(people: env.people, messages: env.messages,
                                 snippets: env.snippets, nudges: env.nudges)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: env.settings)
        }
        .sheet(item: $messages.composer) { draft in
            MessageComposer(draft: draft) { outcome in
                messages.composerFinished(outcome)
            }
            .ignoresSafeArea()
        }
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment.preview())
}
