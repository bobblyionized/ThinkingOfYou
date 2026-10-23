//  SettingsView.swift
//  ThinkingOfYou/UI — your Instagram username, the scroll budget rules,
//  signing out, Contacts / notification status, quick replies and the
//  honest limits of what the app can do.

import SwiftUI

struct SettingsView: View {
    let model: SettingsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingSignOut = false
    @State private var savedCount = 0
    @FocusState private var usernameFocused: Bool

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                if model.isInstagramAppInstalled {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text("The Instagram app is still on this iPhone")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                Text("Your scroll limit only works in here. Offload Instagram in Settings, General, iPhone Storage so it can't be skipped.")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.wine)
                        }
                        .padding(.vertical, Space.xs)
                    }
                    .listRowBackground(Theme.blush)
                }

                usernameSection(draft: $model.usernameDraft)
                budgetSection
                permissionsSection

                Section {
                    NavigationLink {
                        SnippetsView(store: model.snippets)
                    } label: {
                        HStack {
                            Text("Quick replies")
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(model.snippets.snippets.count)")
                                .font(.toyNumber(.subheadline, weight: .regular))
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                } header: {
                    SectionHeading(title: "Messages")
                }
                .listRowBackground(Theme.card)

                accountSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Sign out of Instagram?",
                                isPresented: $confirmingSignOut,
                                titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await model.signOutOfInstagram() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears Instagram's cookies and data in Thinking Of You. You'll sign in again next time.")
            }
        }
        .tint(Theme.wine)
        .sensoryFeedback(.success, trigger: savedCount)
        .onAppear { model.onAppear() }
    }

    // MARK: Username

    private func usernameSection(draft: Binding<String>) -> some View {
        Section {
            HStack {
                Text("Blocked profile")
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(model.effectiveUsernameText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(model.detectedUsername == nil && model.manualUsername == nil
                                     ? Theme.inkSoft : Theme.wine)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: Space.xs) {
                Text("@")
                    .foregroundStyle(Theme.inkSoft)
                    .accessibilityHidden(true)
                TextField(model.detectedUsername ?? "username", text: draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .focused($usernameFocused)
                    .onSubmit { save() }
                    .accessibilityLabel("Instagram username")
                Button("Save") { save() }
                    .buttonStyle(.soft)
            }

            if let error = model.usernameError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.wine)
            }

            if model.manualUsername != nil, let detected = model.detectedUsername {
                Button("Use detected @\(detected) instead") {
                    model.useDetectedUsername()
                }
                .foregroundStyle(Theme.wine)
            }
        } header: {
            SectionHeading(title: "Your Instagram")
        } footer: {
            Text(usernameFooter)
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
        }
        .listRowBackground(Theme.card)
    }

    private var usernameFooter: String {
        if model.manualUsername != nil {
            return "You set this name yourself. Your own profile stays closed so it can't become a feed. Leave the field empty and save to go back to automatic."
        }
        if model.detectedUsername != nil {
            return "Found automatically after you signed in. Your own profile stays closed so it can't become a feed."
        }
        return "It's found automatically after you sign in. If it isn't, type it here so your own profile stays closed."
    }

    private func save() {
        if model.saveUsername() {
            usernameFocused = false
            savedCount += 1
        }
    }

    // MARK: Budget

    private var budgetSection: some View {
        Section {
            HStack(spacing: Space.l) {
                DrainingHeart(fraction: model.budget.dailyFraction, lineWidth: 1)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("\(model.budget.dailyRemainingText) left today")
                        .font(.toyNumber(.body))
                        .foregroundStyle(Theme.ink)
                    Text("\(model.budget.vaultShortText) in the vault")
                        .font(.toyNumber(.footnote, weight: .regular))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.vertical, Space.xs)
            .accessibilityElement(children: .combine)

            Text(model.budgetRulesText)
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeading(title: "Scroll budget")
        }
        .listRowBackground(Theme.card)
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        Section {
            StatusRow(title: "Contacts",
                      systemImage: "person.2",
                      status: contactsText,
                      isOn: model.contactsAccess.canRead)
            StatusRow(title: "Notifications",
                      systemImage: "bell",
                      status: notificationsText,
                      isOn: model.notificationAccess == .authorized)
            Button("Open iPhone Settings") { model.openSystemSettings() }
                .foregroundStyle(Theme.wine)
        } header: {
            SectionHeading(title: "Permissions")
        } footer: {
            Text("Contacts show your people in Messages mode. Notifications deliver nudges.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
        }
        .listRowBackground(Theme.card)
    }

    private var contactsText: String {
        switch model.contactsAccess {
        case .authorized: return "Allowed"
        case .limited: return "Some contacts"
        case .notDetermined: return "Not asked yet"
        case .denied: return "Off"
        case .restricted: return "Restricted"
        }
    }

    private var notificationsText: String {
        switch model.notificationAccess {
        case .authorized: return "Allowed"
        case .notDetermined: return "Not asked yet"
        case .denied: return "Off"
        }
    }

    // MARK: Account

    private var accountSection: some View {
        Section {
            Button(role: .destructive) {
                confirmingSignOut = true
            } label: {
                HStack {
                    Text("Sign out of Instagram")
                    Spacer()
                    if model.isSigningOut {
                        ProgressView()
                    }
                }
            }
            .disabled(model.isSigningOut)
        } header: {
            SectionHeading(title: "Account")
        }
        .listRowBackground(Theme.card)
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            ForEach(SettingsViewModel.platformLimits, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.rose)
                        .accessibilityHidden(true)
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Space.xxs)
            }
            HStack {
                Text("Version")
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(model.appVersion)
                    .font(.toyNumber(.subheadline, weight: .regular))
                    .foregroundStyle(Theme.inkSoft)
            }
        } header: {
            SectionHeading(title: "What this app can and can't do")
        }
        .listRowBackground(Theme.card)
    }
}

private struct StatusRow: View {
    let title: String
    let systemImage: String
    let status: String
    let isOn: Bool

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Theme.ink)
            Spacer()
            HStack(spacing: Space.xs) {
                Circle()
                    .fill(isOn ? Theme.rose : Theme.hairline)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SettingsView(model: AppEnvironment.preview().settings)
}
