import AuthenticationServices
import SwiftUI
import VPassCore

struct AutoFillPickerView: View {
    @ObservedObject var model: AutoFillModel
    @StateObject private var authenticator = AppAuthenticator()

    var body: some View {
        NavigationStack {
            Group {
                if !authenticator.isUnlocked {
                    lockedView
                } else if model.directRecordID != nil {
                    ProgressView()
                } else {
                    recordList
                }
            }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.cancel() }
                }
            }
        }
        .onChange(of: model.isOnScreen) { _, isOnScreen in
            if isOnScreen {
                authenticator.authenticate(reason: "Unlock VPass to fill your login.")
            }
        }
        .onChange(of: authenticator.isUnlocked) { _, isUnlocked in
            if isUnlocked {
                model.didUnlock()
            }
        }
    }

    private var lockedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("VPass is Locked")
                .font(.title3.bold())
            if let error = authenticator.errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                authenticator.authenticate(reason: "Unlock VPass to fill your login.")
            } label: {
                Label("Unlock", systemImage: "faceid")
            }
            .buttonStyle(.borderedProminent)
            .disabled(authenticator.isAuthenticating)
        }
        .padding()
    }

    private var recordList: some View {
        List {
            if let error = model.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            if !model.suggested.isEmpty {
                Section(model.site.map { "Suggested for \($0)" } ?? "Suggested") {
                    ForEach(model.suggested) { row(for: $0) }
                }
            }
            if !model.others.isEmpty {
                Section(model.suggested.isEmpty ? "All" : "Other") {
                    ForEach(model.others) { row(for: $0) }
                }
            }
        }
        .searchable(text: $model.searchText)
        .overlay {
            if model.records.isEmpty && model.errorMessage == nil {
                ContentUnavailableView(
                    model.mode == .oneTimeCode ? "No Verification Codes" : "No Passwords",
                    systemImage: "key",
                    description: Text("Add logins in the VPass app, then try again.")
                )
            } else if model.suggested.isEmpty && model.others.isEmpty && !model.searchText.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
    }

    private func row(for record: CredentialRecord) -> some View {
        Button {
            model.select(record)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.title.isEmpty ? record.autofillUser : record.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if record.id == model.bestMatch?.id {
                        Text("Best match")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.blue, in: Capsule())
                    }
                }
                Text(subtitle(for: record))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func subtitle(for record: CredentialRecord) -> String {
        let parts = [record.autofillUser, record.autofillDomain ?? ""].filter { !$0.isEmpty }
        return parts.joined(separator: " - ")
    }
}

struct AutoFillConfigurationView: View {
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "key.viewfinder")
                    .font(.system(size: 52))
                    .foregroundStyle(.blue)
                Text("VPass AutoFill is On")
                    .font(.title2.bold())
                Text("Tap a username, password, or verification code field and choose VPass above the keyboard. VPass asks for Face ID before it fills anything.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .task {
            if let records = try? VaultKeychainStore().loadRecords() {
                await CredentialIdentitySync.update(with: records)
            }
        }
    }
}
