import LocalAuthentication
import SwiftUI
import VPassCore

/// Touch ID / Mac password gate for the extension. The app's own
/// AppAuthenticator tracks idle time through AppKit, which an extension
/// should not do, so this is a minimal one-shot version.
@MainActor
final class AutoFillAuthenticator: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var errorMessage: String?

    func authenticate() {
        guard !isUnlocked, !isAuthenticating else {
            return
        }
        isAuthenticating = true
        errorMessage = nil
        Task {
            do {
                // macOS shows this as "VPass is trying to fill your login."
                try await Self.evaluate(reason: "fill your login")
                isUnlocked = true
            } catch {
                if !Self.isCancellation(error) {
                    errorMessage = error.localizedDescription
                }
            }
            isAuthenticating = false
        }
    }

    private nonisolated static func evaluate(reason: String) async throws {
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            throw authError ?? LAError(.authenticationFailed)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? LAError(.authenticationFailed))
                }
            }
        }
    }

    private nonisolated static func isCancellation(_ error: Error) -> Bool {
        guard let laError = error as? LAError else {
            return false
        }
        return laError.code == .userCancel || laError.code == .systemCancel || laError.code == .appCancel
    }
}

struct AutoFillPickerView: View {
    @ObservedObject var model: AutoFillModel
    @StateObject private var authenticator = AutoFillAuthenticator()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.blue)
                Text(model.title)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            Group {
                if !authenticator.isUnlocked {
                    lockedView
                } else if model.directRecordID != nil {
                    ProgressView()
                } else {
                    recordList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                if authenticator.isUnlocked, model.directRecordID == nil, let best = model.bestMatch {
                    Button("Fill \(best.title.isEmpty ? best.autofillUser : best.title)") { model.select(best) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
        }
        .frame(minWidth: 420, minHeight: 460)
        .onChange(of: model.isOnScreen) { _, isOnScreen in
            if isOnScreen {
                authenticator.authenticate()
            }
        }
        .onChange(of: authenticator.isUnlocked) { _, isUnlocked in
            if isUnlocked {
                model.didUnlock()
            }
        }
    }

    private var lockedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "touchid")
                .font(.system(size: 44))
                .foregroundStyle(.blue)
            Text("VPass is Locked")
                .font(.title3.bold())
            if let error = authenticator.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Unlock") { authenticator.authenticate() }
                .keyboardShortcut(.defaultAction)
                .disabled(authenticator.isAuthenticating)
        }
        .padding()
    }

    private var recordList: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if let best = model.bestMatch {
                        model.select(best)
                    }
                }
                .padding(12)

            List {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
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
    }

    private func row(for record: CredentialRecord) -> some View {
        Button {
            model.select(record)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.title.isEmpty ? record.autofillUser : record.title)
                    if record.id == model.bestMatch?.id {
                        Text("Best match")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.blue, in: Capsule())
                    }
                }
                Text([record.autofillUser, record.autofillDomain ?? ""].filter { !$0.isEmpty }.joined(separator: " - "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

struct AutoFillConfigurationView: View {
    let loadRecords: () throws -> [CredentialRecord]
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("VPass AutoFill is On")
                .font(.title2.bold())
            Text("Click a username, password, or verification code field in Safari or another app and choose VPass. VPass asks for Touch ID or your Mac password before it fills anything.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done", action: onDone)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 420)
        .task {
            if let records = try? loadRecords() {
                await CredentialIdentitySync.update(with: records)
            }
        }
    }
}
