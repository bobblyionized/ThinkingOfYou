//  NudgesView.swift
//  ThinkingOfYou/UI — scheduled "Text <name>" reminders: the list of pending
//  nudges, and the sheet that schedules one for a person.

import SwiftUI

// MARK: - Pending nudges

struct NudgesView: View {
    let model: NudgesViewModel

    var body: some View {
        List {
            accessNotice

            if model.pending.isEmpty {
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else {
                    emptyState
                }
            } else {
                Section {
                    ForEach(model.pending) { nudge in
                        NudgeRow(nudge: nudge)
                            .listRowBackground(Theme.card)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await model.cancel(nudge) }
                                } label: {
                                    Label("Cancel nudge", systemImage: "bell.slash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await model.cancel(nudge) }
                                } label: {
                                    Label("Cancel nudge", systemImage: "bell.slash")
                                }
                            }
                    }
                } header: {
                    SectionHeading(title: "Coming up",
                                   detail: model.pending.count == 1 ? "1 nudge" : "\(model.pending.count) nudges")
                } footer: {
                    Text("Swipe left on a nudge to cancel it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle("Nudges")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.onAppear() }
        .refreshable { await model.refresh() }
        .alert("Nudge not scheduled",
               isPresented: Binding(
                   get: { model.errorMessage != nil },
                   set: { if !$0 { model.errorMessage = nil } }
               )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var accessNotice: some View {
        switch model.access {
        case .denied:
            NoticeCard(systemImage: "bell.slash",
                       title: "Notifications are off",
                       message: "Nudges arrive as notifications. Turn them on for Thinking Of You in Settings.",
                       buttonTitle: "Open Settings") {
                model.openSystemSettings()
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Space.s, leading: 0, bottom: Space.s, trailing: 0))
        case .notDetermined:
            NoticeCard(systemImage: "bell.badge",
                       title: "Get a nudge to reach out",
                       message: "A nudge is a notification that says who to text. Tap it and the message opens, ready to send.",
                       buttonTitle: "Allow notifications") {
                Task { await model.requestAccess() }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Space.s, leading: 0, bottom: Space.s, trailing: 0))
        case .authorized:
            EmptyView()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("No nudges yet")
                .font(.toyDisplay(.title3))
                .foregroundStyle(Theme.ink)
            Text("In Messages, swipe left on someone and tap Nudge, or touch and hold their name and choose Remind me to text.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Space.s)
        .listRowBackground(Color.clear)
    }
}

private struct NudgeRow: View {
    let nudge: Nudge

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Text \(nudge.name)")
                .font(.toyDisplay(.headline))
                .foregroundStyle(Theme.ink)
            Label(NudgesViewModel.scheduleText(for: nudge),
                  systemImage: nudge.repeats == .never ? "bell" : "repeat")
                .labelStyle(SmallIconLabelStyle())
                .font(.toyNumber(.footnote, weight: .medium))
                .foregroundStyle(Theme.wine)
            if !nudge.body.isEmpty {
                Text("\u{201C}\(nudge.body)\u{201D}")
                    .font(.system(.subheadline, design: .serif).italic())
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Schedule a nudge

struct NudgeScheduleView: View {
    let person: Person
    let model: NudgesViewModel
    let snippets: SnippetsStore
    let onDone: () -> Void

    @State private var isScheduling = false
    @State private var scheduledCount = 0

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                Section {
                    HStack(spacing: Space.m) {
                        AvatarView(person: person, size: 52, ringed: true)
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text("Text \(person.shortName)")
                                .font(.toyDisplay(.title2))
                                .foregroundStyle(Theme.ink)
                            Text("You'll get a notification. Tap it and a message to \(person.shortName) opens, ready to send.")
                                .font(.footnote)
                                .foregroundStyle(Theme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, Space.xs)
                    .accessibilityElement(children: .combine)
                }
                .listRowBackground(Color.clear)

                Section {
                    DatePicker("Remind me",
                               selection: $model.draftDate,
                               in: Date()...,
                               displayedComponents: [.date, .hourAndMinute])
                    Picker("Repeat", selection: $model.draftRepeat) {
                        ForEach(NudgeRepeat.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Repeat")
                } header: {
                    SectionHeading(title: "When")
                }
                .listRowBackground(Theme.card)

                Section {
                    TextField("What you'd like to say (optional)",
                              text: $model.draftBody,
                              axis: .vertical)
                        .lineLimit(2...5)
                    if !snippets.snippets.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Space.s) {
                                ForEach(snippets.snippets) { snippet in
                                    Button(snippet.text) {
                                        model.draftBody = snippet.text
                                    }
                                    .buttonStyle(.soft)
                                    .lineLimit(1)
                                    .accessibilityHint("Uses this as the message")
                                }
                            }
                            .padding(.vertical, Space.xxs)
                        }
                        .listRowInsets(EdgeInsets(top: Space.s, leading: Space.l, bottom: Space.s, trailing: Space.l))
                    }
                } header: {
                    SectionHeading(title: "Message")
                } footer: {
                    Text("The message is filled in for you. Nothing is sent until you tap Send.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                }
                .listRowBackground(Theme.card)

                let existing = model.nudges(for: person.id)
                if !existing.isEmpty {
                    Section {
                        ForEach(existing) { nudge in
                            HStack {
                                Text(NudgesViewModel.scheduleText(for: nudge))
                                    .font(.toyNumber(.subheadline, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Button("Cancel") {
                                    Task { await model.cancel(nudge) }
                                }
                                .buttonStyle(.soft)
                                .accessibilityLabel("Cancel nudge for \(NudgesViewModel.scheduleText(for: nudge))")
                            }
                        }
                    } header: {
                        SectionHeading(title: "Already scheduled")
                    }
                    .listRowBackground(Theme.card)
                }

                if model.access == .denied {
                    Section {
                        Button("Turn on notifications in Settings") { model.openSystemSettings() }
                            .foregroundStyle(Theme.wine)
                    } footer: {
                        Text("Nudges can't arrive while notifications are off.")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle("New nudge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.resetDraft()
                        onDone()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isScheduling {
                        ProgressView()
                    } else {
                        Button("Schedule") { schedule() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .alert("Nudge not scheduled",
                   isPresented: Binding(
                       get: { model.errorMessage != nil },
                       set: { if !$0 { model.errorMessage = nil } }
                   )) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .tint(Theme.wine)
        .sensoryFeedback(.success, trigger: scheduledCount)
        .onAppear { model.resetDraft() }
    }

    private func schedule() {
        isScheduling = true
        Task {
            let ok = await model.schedule(for: person)
            isScheduling = false
            if ok {
                scheduledCount += 1
                onDone()
            }
        }
    }
}

#Preview("Nudges") {
    NavigationStack {
        NudgesView(model: AppEnvironment.preview().nudges)
    }
}

#Preview("Schedule") {
    let env = AppEnvironment.preview()
    return NudgeScheduleView(person: Person.samples[0], model: env.nudges, snippets: env.snippets) {}
}
