//  MessagesView.swift
//  ThinkingOfYou/UI — Messages mode: a launcher for iMessage. Pinned people
//  as a row of avatars, search, everyone else via PersonRowView, shortcuts
//  to quick replies and nudges, and the Contacts permission states.
//  The composer sheet itself is attached once in RootView.

import SwiftUI

struct MessagesView: View {
    let people: PeopleViewModel
    let messages: MessagesViewModel
    let snippets: SnippetsStore
    let nudges: NudgesViewModel
    /// Owned by RootView so it can close these sheets for the composer.
    @Binding var sheet: MessagesSheet?
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var people = people

        List {
            header(search: $people.searchText)
                .plainRow(top: Space.l, bottom: Space.s)

            if people.access.canRead {
                readableContent
            } else {
                permissionCard
                    .plainRow(top: Space.m, bottom: Space.l)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .scrollDismissesKeyboard(.immediately)
        .environment(\.defaultMinListRowHeight, 1)
        .refreshable {
            await people.reload()
        }
        .task {
            await people.onAppear()
            await nudges.onAppear()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: people.pinnedIDs)
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
    }

    // MARK: Header + search

    private func header(search: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Who's on your mind?")
                .font(.toyDisplay(.largeTitle))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if people.access.canRead {
                HStack(spacing: Space.s) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.inkSoft)
                        .accessibilityHidden(true)
                    TextField("Search people", text: search)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(Theme.ink)
                    if !search.wrappedValue.isEmpty {
                        Button {
                            search.wrappedValue = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, Space.m + 2)
                .frame(minHeight: 44)
                .background(Capsule().fill(Theme.card))
                .overlay(Capsule().strokeBorder(searchFocused ? Theme.rose : Theme.hairline, lineWidth: 1))
                .animation(Motion.snap, value: searchFocused)
            }
        }
    }

    // MARK: Contacts readable

    @ViewBuilder
    private var readableContent: some View {
        if let error = people.errorMessage {
            NoticeCard(systemImage: "exclamationmark.bubble",
                       title: "Contacts didn't load",
                       message: error,
                       buttonTitle: "Try again") {
                Task { await people.reload() }
            }
            .plainRow(top: Space.s, bottom: Space.m)
        }

        if !people.isSearching {
            pinnedSection
            shortcuts
                .plainRow(top: Space.s, bottom: Space.m)
        }

        let list = people.isSearching ? people.filteredPeople : people.otherPeople

        if people.isLoading && !people.hasLoaded {
            HStack(spacing: Space.s) {
                ProgressView()
                Text("Gathering your people")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .plainRow(top: Space.xl, bottom: Space.xl)
        } else if !list.isEmpty {
            SectionHeading(title: people.isSearching ? "Results" : "Everyone",
                           detail: people.isSearching ? "\(list.count)" : nil)
                .plainRow(top: Space.m, bottom: Space.xs)
            ForEach(list) { person in
                row(for: person)
            }
        } else if people.isSearching {
            Text("No one matches \u{201C}\(people.searchText)\u{201D}. Try a first name, nickname or the last digits of a number.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .plainRow(top: Space.l, bottom: Space.l)
        } else if people.hasLoaded && people.people.isEmpty {
            NoticeCard(systemImage: "person.crop.circle.badge.plus",
                       title: "No contacts yet",
                       message: "Add people in the Contacts app and they'll show up here.")
                .plainRow(top: Space.s, bottom: Space.l)
        }

        if people.access == .limited {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("You've shared some of your contacts. Choose more in Settings.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings") { people.openSystemSettings() }
                    .buttonStyle(.soft)
            }
            .plainRow(top: Space.l, bottom: Space.xl)
        }
    }

    private func row(for person: Person) -> some View {
        let pinned = people.isPinned(person)
        return PersonRowView(person: person,
                             isPinned: pinned,
                             messages: messages,
                             snippets: snippets.snippets,
                             nudgeText: nextNudgeText(for: person))
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Theme.hairline)
            .listRowInsets(EdgeInsets(top: Space.xs, leading: Space.l, bottom: Space.xs, trailing: Space.l))
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    people.togglePin(person)
                } label: {
                    Label(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin")
                }
                .tint(Theme.roseFill)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    sheet = .schedule(person)
                } label: {
                    Label("Nudge", systemImage: "bell")
                }
                .tint(Theme.wine)
            }
            .contextMenu {
                personMenu(person)
            }
    }

    private func nextNudgeText(for person: Person) -> String? {
        nudges.nudges(for: person.id).first.map { NudgesViewModel.scheduleText(for: $0) }
    }

    // MARK: Pinned

    @ViewBuilder
    private var pinnedSection: some View {
        let pinned = people.pinnedPeople
        if !pinned.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Space.l) {
                    ForEach(Array(pinned.enumerated()), id: \.element.id) { index, person in
                        PinnedAvatar(person: person) {
                            messages.message(person)
                        }
                        .contextMenu {
                            personMenu(person)
                            Divider()
                            if index > 0 {
                                Button {
                                    people.movePinned(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                                } label: {
                                    Label("Move earlier", systemImage: "arrow.left")
                                }
                            }
                            if index < pinned.count - 1 {
                                Button {
                                    people.movePinned(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                                } label: {
                                    Label("Move later", systemImage: "arrow.right")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.s)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Pinned people")
        } else if !people.people.isEmpty {
            Label("Swipe right on a name to pin the people you talk to most.", systemImage: "pin")
                .labelStyle(SmallIconLabelStyle())
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .plainRow(top: Space.xs, bottom: Space.xs)
        }
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        HStack(spacing: Space.s) {
            Button {
                sheet = .snippets
            } label: {
                Label("Quick replies", systemImage: "text.bubble")
            }
            .buttonStyle(.soft)

            Button {
                sheet = .nudges
            } label: {
                Label(nudges.pending.isEmpty ? "Nudges" : "Nudges \(nudges.pending.count)",
                      systemImage: "bell")
            }
            .buttonStyle(.soft)
            .accessibilityLabel(nudges.pending.isEmpty ? "Nudges" : "Nudges, \(nudges.pending.count) scheduled")

            Spacer(minLength: 0)
        }
    }

    // MARK: Permission

    @ViewBuilder
    private var permissionCard: some View {
        switch people.access {
        case .notDetermined:
            NoticeCard(systemImage: "person.2.fill",
                       title: "Bring your people here",
                       message: "Allow Contacts to see names and photos, pin the people you love, and message or call them in one tap.",
                       buttonTitle: "Allow Contacts") {
                Task { await people.requestAccess() }
            }
        case .denied:
            NoticeCard(systemImage: "person.crop.circle.badge.xmark",
                       title: "Contacts are turned off",
                       message: "Turn on Contacts for Thinking Of You in Settings to see your people here.",
                       buttonTitle: "Open Settings") {
                people.openSystemSettings()
            }
        case .restricted:
            NoticeCard(systemImage: "lock.circle",
                       title: "Contacts are restricted",
                       message: "Screen Time or a device profile is blocking Contacts on this iPhone. Check Settings to change it.",
                       buttonTitle: "Open Settings") {
                people.openSystemSettings()
            }
        case .authorized, .limited:
            EmptyView()
        }
    }

    // MARK: Person menu (shared by rows and pinned avatars)

    @ViewBuilder
    private func personMenu(_ person: Person) -> some View {
        Button {
            messages.perform(.message, for: person)
        } label: {
            Label(PersonAction.message.title, systemImage: PersonAction.message.systemImage)
        }
        .disabled(!messages.isAvailable(.message, for: person))

        if !snippets.snippets.isEmpty {
            Menu {
                ForEach(snippets.snippets) { snippet in
                    Button(snippet.text) {
                        messages.message(person, body: snippet.text)
                    }
                }
            } label: {
                Label("Quick reply", systemImage: "text.bubble")
            }
            .disabled(!messages.isAvailable(.message, for: person))
        }

        ForEach([PersonAction.call, .faceTime, .faceTimeAudio, .openInMessages]) { action in
            Button {
                messages.perform(action, for: person)
            } label: {
                Label(action.title, systemImage: action.systemImage)
            }
            .disabled(!messages.isAvailable(action, for: person))
        }

        Divider()

        Button {
            sheet = .schedule(person)
        } label: {
            Label("Remind me to text", systemImage: "bell")
        }

        Button {
            people.togglePin(person)
        } label: {
            if people.isPinned(person) {
                Label("Unpin", systemImage: "pin.slash")
            } else {
                Label("Pin", systemImage: "pin")
            }
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ item: MessagesSheet) -> some View {
        switch item {
        case .snippets:
            NavigationStack {
                SnippetsView(store: snippets)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { sheet = nil }
                        }
                    }
            }
            .tint(Theme.wine)
        case .nudges:
            NavigationStack {
                NudgesView(model: nudges)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { sheet = nil }
                        }
                    }
            }
            .tint(Theme.wine)
        case .schedule(let person):
            NudgeScheduleView(person: person, model: nudges, snippets: snippets) {
                sheet = nil
            }
            .presentationDetents([.large])
        }
    }
}

// MARK: - Sheet routing

enum MessagesSheet: Identifiable, Hashable {
    case snippets
    case nudges
    case schedule(Person)

    var id: String {
        switch self {
        case .snippets: return "snippets"
        case .nudges: return "nudges"
        case .schedule(let person): return "schedule-\(person.id)"
        }
    }
}

// MARK: - Pinned avatar

private struct PinnedAvatar: View {
    let person: Person
    let onTap: () -> Void

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 58
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            onTap()
        } label: {
            VStack(spacing: Space.s) {
                AvatarView(person: person, size: size, ringed: true)
                Text(person.shortName)
                    .font(.toyDisplay(.footnote, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: size + Space.l)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityLabel(person.displayName)
        .accessibilityHint("Opens a new message. Touch and hold for more.")
    }
}

// MARK: - Row helper

private extension View {
    /// A list row with no background, separator or default insets.
    func plainRow(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: Space.l, bottom: bottom, trailing: Space.l))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return MessagesView(people: env.people, messages: env.messages,
                        snippets: env.snippets, nudges: env.nudges,
                        sheet: .constant(nil))
        .environment(env)
}
