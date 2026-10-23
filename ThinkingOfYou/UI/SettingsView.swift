//  SettingsView.swift
//  ThinkingOfYou/UI — STUB (Core). The UI agent replaces this file.

import SwiftUI

struct SettingsView: View {
    let model: SettingsViewModel

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Your Instagram username") {
                Text(model.effectiveUsernameText)
                TextField("username", text: $model.usernameDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save") { model.saveUsername() }
                if let error = model.usernameError { Text(error) }
            }
            Section("About") {
                ForEach(SettingsViewModel.platformLimits, id: \.self) { Text($0) }
            }
        }
        .onAppear { model.onAppear() }
    }
}
