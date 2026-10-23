//  PersonRowView.swift
//  ThinkingOfYou/UI — one person in the Messages list: avatar, name, next
//  nudge or best handle, and Message / Call / FaceTime buttons.
//  Long-press Message for quick replies or another number; long-press
//  FaceTime for audio or the Messages app.

import SwiftUI

struct PersonRowView: View {
    let person: Person
    var isPinned: Bool = false
    let messages: MessagesViewModel
    /// Quick replies offered from the Message button's menu.
    var snippets: [Snippet] = []
    /// "Tomorrow, 7:00 PM" when a nudge is scheduled for this person.
    var nudgeText: String? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var taps = 0

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.m))
            : AnyLayout(HStackLayout(spacing: Space.m))

        layout {
            identity
            actions
        }
        .padding(.vertical, Space.xs)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }

    // MARK: Identity (tap = Message)

    private var identity: some View {
        Button {
            taps += 1
            messages.message(person)
        } label: {
            HStack(spacing: Space.m) {
                AvatarView(person: person, size: 46)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    HStack(spacing: Space.xs) {
                        Text(person.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.rose)
                                .accessibilityHidden(true)
                        }
                    }
                    subtitle
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName)
        .accessibilityHint(person.canMessage ? "Opens a new message" : "")
    }

    @ViewBuilder
    private var subtitle: some View {
        if let nudgeText {
            Label(nudgeText, systemImage: "bell.fill")
                .labelStyle(SmallIconLabelStyle())
                .font(.footnote)
                .foregroundStyle(Theme.wine)
                .lineLimit(1)
        } else if let handle = person.handles.first {
            Text(handle.label.isEmpty ? handle.value : "\(handle.label)  \(handle.value)")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
        } else {
            Text("No number or email")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var accessibilityName: String {
        var parts = [person.displayName]
        if isPinned { parts.append("pinned") }
        if let nudgeText { parts.append("nudge \(nudgeText)") }
        return parts.joined(separator: ", ")
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: Space.s) {
            messageMenu

            Button {
                taps += 1
                messages.perform(.call, for: person)
            } label: {
                Image(systemName: PersonAction.call.systemImage)
            }
            .buttonStyle(.circleIcon)
            .disabled(!messages.isAvailable(.call, for: person))
            .accessibilityLabel("Call \(person.shortName)")

            faceTimeMenu
        }
    }

    private var messageMenu: some View {
        Menu {
            if !snippets.isEmpty {
                Section("Quick reply") {
                    ForEach(snippets) { snippet in
                        Button(snippet.text) {
                            taps += 1
                            messages.message(person, body: snippet.text)
                        }
                    }
                }
            }
            if person.handles.count > 1 {
                Section("Send to") {
                    ForEach(person.handles) { handle in
                        Button {
                            taps += 1
                            messages.message(person, handle: handle)
                        } label: {
                            Label(handle.label.isEmpty ? handle.value : "\(handle.label): \(handle.value)",
                                  systemImage: handle.kind == .phone ? "phone" : "envelope")
                        }
                    }
                }
            }
        } label: {
            CircleIcon(systemImage: PersonAction.message.systemImage,
                       enabled: messages.isAvailable(.message, for: person))
        } primaryAction: {
            taps += 1
            messages.perform(.message, for: person)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(!messages.isAvailable(.message, for: person))
        .accessibilityLabel("Message \(person.shortName)")
        .accessibilityHint("Touch and hold for quick replies")
    }

    private var faceTimeMenu: some View {
        Menu {
            ForEach([PersonAction.faceTimeAudio, .openInMessages]) { action in
                Button {
                    taps += 1
                    messages.perform(action, for: person)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
                .disabled(!messages.isAvailable(action, for: person))
            }
        } label: {
            CircleIcon(systemImage: PersonAction.faceTime.systemImage,
                       enabled: messages.isAvailable(.faceTime, for: person))
        } primaryAction: {
            taps += 1
            messages.perform(.faceTime, for: person)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(!messages.isAvailable(.faceTime, for: person))
        .accessibilityLabel("FaceTime \(person.shortName)")
        .accessibilityHint("Touch and hold for FaceTime Audio")
    }
}

/// The circle used for menu-backed action buttons (matches CircleIconButtonStyle).
struct CircleIcon: View {
    let systemImage: String
    var enabled: Bool = true
    var diameter: CGFloat = 38

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: diameter * 0.40, weight: .semibold))
            .foregroundStyle(Theme.wine)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(Theme.blush))
            .opacity(enabled ? 1 : 0.3)
            .contentShape(Circle())
    }
}

/// Icon and title close together, icon a touch smaller.
struct SmallIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.xs) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return List {
        ForEach(Person.samples) { person in
            PersonRowView(person: person,
                          isPinned: person.id == "sample-ada",
                          messages: env.messages,
                          snippets: env.snippets.snippets,
                          nudgeText: person.id == "sample-mum" ? "Tomorrow, 7:00 PM" : nil)
        }
    }
    .listStyle(.plain)
}
